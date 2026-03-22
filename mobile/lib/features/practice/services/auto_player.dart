import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../midi/services/midi_service.dart';
import '../../score/models/score.dart';
import '../../settings/services/app_settings.dart';
import 'audio_synth_service.dart';

/// 调度的 MIDI 事件
class ScheduledMidiEvent {
  final int noteNumber;
  final int velocity;
  final int absoluteMs; // 从曲首开始的绝对毫秒数
  final bool isNoteOn;
  final int measureNumber;

  const ScheduledMidiEvent({
    required this.noteNumber,
    required this.velocity,
    required this.absoluteMs,
    required this.isNoteOn,
    required this.measureNumber,
  });
}

/// 播放音符事件 (驱动虚拟键盘高亮)
class PlayingNoteEvent {
  final int noteNumber;
  final bool isOn; // true=noteOn, false=noteOff

  const PlayingNoteEvent({required this.noteNumber, required this.isOn});
}

/// 自动播放状态
class AutoPlayState {
  final bool isPlaying;
  final bool isPaused;
  final double progress; // 0.0 - 1.0
  final int currentMeasure;
  final int totalMeasures;
  final double playbackRate;
  final Duration position;
  final Duration duration;
  final bool loopEnabled;

  const AutoPlayState({
    required this.isPlaying,
    required this.isPaused,
    required this.progress,
    required this.currentMeasure,
    required this.totalMeasures,
    required this.playbackRate,
    required this.position,
    required this.duration,
    this.loopEnabled = false,
  });

  AutoPlayState.initial()
      : isPlaying = false,
        isPaused = false,
        progress = 0,
        currentMeasure = 1,
        totalMeasures = 0,
        playbackRate = 1.0,
        position = Duration.zero,
        duration = Duration.zero,
        loopEnabled = false;
}

/// 自动播放器
///
/// 从 Score 生成 MIDI 事件序列，按时间调度发送，驱动 OSMD 跟随。
///
/// 时钟方案 (优化后):
/// - 使用 Stopwatch 微秒级精度计时，避免整数截断误差
/// - 使用 "schedule-next-event" 策略：计算下一个事件的触发时间，
///   用单次 Timer 精确调度，而非固定周期轮询
/// - 预调度窗口 (lookahead) 容纳 Timer jitter，确保事件不遗漏
/// - UI 状态更新节流为 ~33fps，避免过度重建
class AutoPlayer {
  final Score score;
  final MidiService _midiService = MidiService();

  late List<ScheduledMidiEvent> _events;
  int _eventIndex = 0;

  bool _isPlaying = false;
  bool _isPaused = false;
  double _playbackRate = 1.0;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _tickTimer;
  int _elapsedBaseMs = 0; // 暂停恢复时的已播放毫秒

  int _currentMeasure = 1;
  int _totalDurationMs = 0;

  // 循环播放
  int? _loopStartMs;
  int? _loopEndMs;
  bool _loopEnabled = false;

  // 预调度窗口：Timer jitter 容忍度 (ms)
  // Timer 虽然设置了 Nms 后触发，实际可能延迟 Mms
  // 用 lookahead 窗口提前处理"快到了"的事件，避免因 Timer 延迟导致音符丢失
  static const int _lookaheadMs = 25;

  // UI 状态更新最小间隔 (ms) — 限制为 ~33fps
  int _lastStateEmitMs = 0;
  static const int _stateEmitIntervalMs = 30;

  final _audioSynth = AudioSynthService();

  final _stateController = StreamController<AutoPlayState>.broadcast();
  final _measureController = StreamController<int>.broadcast();

  /// 播放状态流
  Stream<AutoPlayState> get stateStream => _stateController.stream;

  /// 当前小节流 (驱动 OSMD 高亮)
  Stream<int> get measureStream => _measureController.stream;

  /// 当前播放音符流 (驱动虚拟键盘高亮)
  Stream<PlayingNoteEvent> get noteStream => _noteController.stream;

  /// 播放中的音符事件
  final _noteController = StreamController<PlayingNoteEvent>.broadcast();

  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  int get currentMeasure => _currentMeasure;
  int get totalMeasures => score.totalMeasures;

  /// 是否有物理 MIDI 设备连接
  bool get hasMidiDevice => _midiService.connectedDevice != null;

  bool get loopEnabled => _loopEnabled;
  int? get loopStartMs => _loopStartMs;
  int? get loopEndMs => _loopEndMs;

  /// 是否应该走 MIDI 输出（设置为 MIDI 且有设备连接）
  bool get _useMidiOutput =>
      AppSettings().audioOutputMode == AudioOutputMode.midi &&
      _midiService.connectedDevice != null;

  AutoPlayer(this.score) {
    _events = _buildScheduledEvents();
    if (_events.isNotEmpty) {
      _totalDurationMs = _events.last.absoluteMs;
    }
    // 异步初始化内置合成器
    _initSynth();
  }

  Future<void> _initSynth() async {
    await _audioSynth.init();
  }

  /// 从乐谱音符生成调度事件列表
  ///
  /// 使用解析器已计算的 startMs 和 durationMs（已按各小节 tempo 正确处理变速）
  List<ScheduledMidiEvent> _buildScheduledEvents() {
    final events = <ScheduledMidiEvent>[];
    final notes = score.allNotes;

    for (final note in notes) {
      // Note On — 使用乐谱中的 velocity
      events.add(ScheduledMidiEvent(
        noteNumber: note.pitchNumber,
        velocity: note.velocity,
        absoluteMs: note.startMs,
        isNoteOn: true,
        measureNumber: note.measureNumber,
      ));

      // Note Off — 使用解析器算好的 durationMs（已按所在小节 tempo 计算）
      events.add(ScheduledMidiEvent(
        noteNumber: note.pitchNumber,
        velocity: 0,
        absoluteMs: note.startMs + note.durationMs,
        isNoteOn: false,
        measureNumber: note.measureNumber,
      ));
    }

    events.sort((a, b) => a.absoluteMs.compareTo(b.absoluteMs));
    return events;
  }

  /// 开始播放
  void play({int fromMeasure = 1, double rate = 1.0}) {
    if (_isPlaying && !_isPaused) return;

    _playbackRate = rate;

    if (_isPaused) {
      // 恢复播放
      _isPaused = false;
      _stopwatch.start();
      if (!_useMidiOutput) {
        _audioSynth.resume();
      }
    } else {
      // 新播放
      _eventIndex = _findStartIndex(fromMeasure);
      _currentMeasure = fromMeasure;
      _elapsedBaseMs = 0;
      _lastStateEmitMs = 0;
      _stopwatch.reset();
      _stopwatch.start();
      if (!_useMidiOutput) {
        _audioSynth.resume();
      }
    }

    _isPlaying = true;
    _tickTimer?.cancel();
    _scheduleNextTick();
    _emitState();
    debugPrint('[AutoPlayer] Playing from measure $fromMeasure at ${rate}x');
  }

  /// 暂停
  void pause() {
    if (!_isPlaying || _isPaused) return;
    _isPaused = true;
    _elapsedBaseMs = _getPlaybackMs();
    _stopwatch.stop();
    _tickTimer?.cancel();
    _emitState();
    debugPrint('[AutoPlayer] Paused at measure $_currentMeasure');

    // 发送所有活跃音符的 noteOff
    _allNotesOff();
    if (!_useMidiOutput) {
      _audioSynth.pause();
    }
  }

  /// 停止
  void stop() {
    _isPlaying = false;
    _isPaused = false;
    _stopwatch.stop();
    _stopwatch.reset();
    _elapsedBaseMs = 0;
    _tickTimer?.cancel();
    _allNotesOff();
    _audioSynth.stop();
    _emitState();
    debugPrint('[AutoPlayer] Stopped');
  }

  /// 变速 (实时生效)
  void setPlaybackRate(double rate) {
    final currentMs = _getPlaybackMs();
    _playbackRate = rate.clamp(0.25, 2.0);
    _elapsedBaseMs = currentMs;
    _stopwatch.reset();
    _stopwatch.start();
    _emitState();
  }

  /// 跳转到指定小节
  void seekToMeasure(int measure) {
    final targetIndex = _findStartIndex(measure);
    if (targetIndex < 0) return;

    _allNotesOff();
    _eventIndex = targetIndex;
    _currentMeasure = measure;

    if (_events.isNotEmpty && targetIndex < _events.length) {
      _elapsedBaseMs = _events[targetIndex].absoluteMs;
    }
    _stopwatch.reset();
    _stopwatch.start();

    _emitState();
  }

  /// 设置循环范围 (小节号)
  void setLoopRange(int startMeasure, int endMeasure) {
    // 找到起始小节第一个事件的时间
    int startMs = 0;
    for (final e in _events) {
      if (e.measureNumber >= startMeasure && e.isNoteOn) {
        startMs = e.absoluteMs;
        break;
      }
    }
    // 找到结束小节最后一个事件的时间
    int endMs = _totalDurationMs;
    for (final e in _events.reversed) {
      if (e.measureNumber <= endMeasure) {
        endMs = e.absoluteMs;
        break;
      }
    }

    _loopStartMs = startMs;
    _loopEndMs = endMs;
    _loopEnabled = true;
    debugPrint('[AutoPlayer] Loop range: measures $startMeasure-$endMeasure (${startMs}ms-${endMs}ms)');
  }

  /// 清除循环
  void clearLoop() {
    _loopStartMs = null;
    _loopEndMs = null;
    _loopEnabled = false;
    debugPrint('[AutoPlayer] Loop cleared');
  }

  /// 切换循环开关
  void toggleLoop() {
    if (_loopEnabled) {
      clearLoop();
    } else {
      // 默认循环当前小节
      setLoopRange(_currentMeasure, _currentMeasure);
    }
  }

  /// 使用微秒级 Stopwatch 计算当前播放时间
  /// 比 elapsedMilliseconds (int 截断) 更精确
  int _getPlaybackMs() {
    // elapsedMicroseconds 是 int，精度 1μs，远超 MIDI 需求
    final elapsedUs = _stopwatch.elapsedMicroseconds;
    final playbackUs = _elapsedBaseMs * 1000 + (elapsedUs * _playbackRate).round();
    return (playbackUs / 1000).round();
  }

  /// 🔑 核心调度: "schedule-next-event" 策略
  ///
  /// 不再用固定 10ms 周期轮询，而是:
  /// 1. 处理当前 lookahead 窗口内的所有事件
  /// 2. 计算下一个事件的触发时间
  /// 3. 用单次 Timer 精确调度到那个时间点
  ///
  /// 好处:
  /// - 无事件时 Timer 不空转，节省 CPU
  /// - 事件密集时（和弦）一次 tick 处理完
  /// - Timer jitter 被 lookahead 窗口吸收
  void _scheduleNextTick() {
    if (!_isPlaying || _isPaused) return;

    // 立即处理当前窗口内的事件
    _tick();

    if (!_isPlaying) return; // _tick 可能触发了 stop

    // 计算到下一个事件的延迟
    if (_eventIndex < _events.length) {
      final playbackMs = _getPlaybackMs();

      // 循环: 如果启用了循环且超出循环范围，跳回循环起点
      if (_loopEnabled && _loopEndMs != null && playbackMs >= _loopEndMs!) {
        _allNotesOff();
        _elapsedBaseMs = _loopStartMs ?? 0;
        _stopwatch.reset();
        _stopwatch.start();
        _eventIndex = _findStartIndexByMs(_loopStartMs ?? 0);
        // 找到循环起点对应的小节
        for (int i = _eventIndex; i < _events.length; i++) {
          if (_events[i].isNoteOn) {
            _currentMeasure = _events[i].measureNumber;
            _measureController.add(_currentMeasure);
            break;
          }
        }
        _scheduleNextTick(); // 立即重新调度
        return;
      }

      final nextEventMs = _events[_eventIndex].absoluteMs;
      // 减去 lookahead 窗口，提前唤醒处理
      int delayMs = ((nextEventMs - playbackMs) / _playbackRate).round() - _lookaheadMs;
      if (delayMs < 1) delayMs = 1; // 最少 1ms，避免忙等

      _tickTimer = Timer(Duration(milliseconds: delayMs), _scheduleNextTick);
    } else {
      // 没有更多事件了，播放结束
      stop();
    }
  }

  void _tick() {
    if (!_isPlaying || _isPaused) return;

    final playbackMs = _getPlaybackMs();

    // 批量发送到达时间点的事件 (包含 lookahead 窗口)
    // lookahead 确保 Timer jitter 不会导致事件延迟播放
    final isMidiMode = _useMidiOutput;

    while (_eventIndex < _events.length) {
      final event = _events[_eventIndex];

      if (event.absoluteMs > playbackMs + _lookaheadMs) {
        break; // 超出 lookahead 窗口，下次再处理
      }

      if (event.isNoteOn) {
        if (isMidiMode) {
          _midiService.sendNoteOn(event.noteNumber, event.velocity);
        } else {
          _audioSynth.noteOn(event.noteNumber, event.velocity);
        }
        _noteController.add(PlayingNoteEvent(noteNumber: event.noteNumber, isOn: true));
      } else {
        if (isMidiMode) {
          _midiService.sendNoteOff(event.noteNumber);
        } else {
          _audioSynth.noteOff(event.noteNumber);
        }
        _noteController.add(PlayingNoteEvent(noteNumber: event.noteNumber, isOn: false));
      }

      if (event.measureNumber != _currentMeasure) {
        _currentMeasure = event.measureNumber;
        _measureController.add(_currentMeasure);
      }

      _eventIndex++;
    }

    // 节流: 限制 UI 状态更新频率 (~33fps)
    if (playbackMs - _lastStateEmitMs >= _stateEmitIntervalMs) {
      _lastStateEmitMs = playbackMs;
      _emitState();
    }
  }

  /// 查找指定小节的起始事件索引
  int _findStartIndex(int measure) {
    for (int i = 0; i < _events.length; i++) {
      if (_events[i].measureNumber >= measure && _events[i].isNoteOn) {
        return i;
      }
    }
    return 0;
  }

  /// 查找指定毫秒时间的起始事件索引
  int _findStartIndexByMs(int ms) {
    for (int i = 0; i < _events.length; i++) {
      if (_events[i].absoluteMs >= ms && _events[i].isNoteOn) {
        return i;
      }
    }
    return 0;
  }

  void _allNotesOff() {
    if (_useMidiOutput) {
      for (int note = 0; note < 128; note++) {
        _midiService.sendNoteOff(note);
      }
    } else {
      _audioSynth.allNotesOff();
    }
  }

  void _emitState() {
    final playbackMs = _totalDurationMs > 0 ? _getPlaybackMs() : 0;
    final progress = _totalDurationMs > 0
        ? (playbackMs / _totalDurationMs).clamp(0.0, 1.0)
        : 0.0;

    _stateController.add(AutoPlayState(
      isPlaying: _isPlaying,
      isPaused: _isPaused,
      progress: progress.toDouble(),
      currentMeasure: _currentMeasure,
      totalMeasures: score.totalMeasures,
      playbackRate: _playbackRate,
      position: Duration(milliseconds: playbackMs),
      duration: Duration(milliseconds: _totalDurationMs),
      loopEnabled: _loopEnabled,
    ));
  }

  void dispose() {
    _tickTimer?.cancel();
    _allNotesOff();
    _audioSynth.dispose();
    _stateController.close();
    _measureController.close();
    _noteController.close();
  }
}
