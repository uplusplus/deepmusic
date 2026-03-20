import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../midi/services/midi_service.dart';
import '../../score/models/score.dart';

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

  const AutoPlayState({
    required this.isPlaying,
    required this.isPaused,
    required this.progress,
    required this.currentMeasure,
    required this.totalMeasures,
    required this.playbackRate,
    required this.position,
    required this.duration,
  });

  AutoPlayState.initial()
      : isPlaying = false,
        isPaused = false,
        progress = 0,
        currentMeasure = 1,
        totalMeasures = 0,
        playbackRate = 1.0,
        position = Duration.zero,
        duration = Duration.zero;
}

/// 自动播放器
///
/// 从 Score 生成 MIDI 事件序列，按时间调度发送，驱动 OSMD 跟随
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

  final _stateController = StreamController<AutoPlayState>.broadcast();
  final _measureController = StreamController<int>.broadcast();

  /// 播放状态流
  Stream<AutoPlayState> get stateStream => _stateController.stream;

  /// 当前小节流 (驱动 OSMD 高亮)
  Stream<int> get measureStream => _measureController.stream;

  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  int get currentMeasure => _currentMeasure;
  int get totalMeasures => score.totalMeasures;

  AutoPlayer(this.score) {
    _events = _buildScheduledEvents();
    if (_events.isNotEmpty) {
      _totalDurationMs = _events.last.absoluteMs;
    }
  }

  /// 从乐谱音符生成调度事件列表
  List<ScheduledMidiEvent> _buildScheduledEvents() {
    final events = <ScheduledMidiEvent>[];
    final notes = score.allNotes;
    final tempo = 120; // 默认 tempo，实际应从 score 获取
    final beatMs = 60000 / tempo;

    for (final note in notes) {
      final durationMs = (note.duration * beatMs).round();

      // Note On
      events.add(ScheduledMidiEvent(
        noteNumber: note.pitchNumber,
        velocity: 80,
        absoluteMs: note.startMs,
        isNoteOn: true,
        measureNumber: note.measureNumber,
      ));

      // Note Off
      events.add(ScheduledMidiEvent(
        noteNumber: note.pitchNumber,
        velocity: 0,
        absoluteMs: note.startMs + durationMs,
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
    } else {
      // 新播放
      _eventIndex = _findStartIndex(fromMeasure);
      _currentMeasure = fromMeasure;
      _elapsedBaseMs = 0;
      _stopwatch.reset();
      _stopwatch.start();
    }

    _isPlaying = true;
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 10), (_) => _tick());
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
    _emitState();
    debugPrint('[AutoPlayer] Stopped');
  }

  /// 变速 (实时生效)
  void setPlaybackRate(double rate) {
    // 变速时需要保存当前播放位置
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

  int _getPlaybackMs() {
    return _elapsedBaseMs + (_stopwatch.elapsedMilliseconds * _playbackRate).round();
  }

  void _tick() {
    if (!_isPlaying || _isPaused) return;

    final playbackMs = _getPlaybackMs();

    // 批量发送同一时间点的事件 (和弦支持)
    while (_eventIndex < _events.length) {
      final event = _events[_eventIndex];
      final adjustedMs = (event.absoluteMs / _playbackRate).round();
      final baseMs = (_elapsedBaseMs / _playbackRate).round();

      if (baseMs + (_stopwatch.elapsedMilliseconds) < (event.absoluteMs / _playbackRate).round()) {
        break;
      }

      if (event.isNoteOn) {
        _midiService.sendNoteOn(event.noteNumber, event.velocity);
      } else {
        _midiService.sendNoteOff(event.noteNumber);
      }

      if (event.measureNumber != _currentMeasure) {
        _currentMeasure = event.measureNumber;
        _measureController.add(_currentMeasure);
      }

      _eventIndex++;
    }

    _emitState();

    // 播放完毕
    if (_eventIndex >= _events.length) {
      stop();
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

  void _allNotesOff() {
    for (int note = 0; note < 128; note++) {
      _midiService.sendNoteOff(note);
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
    ));
  }

  void dispose() {
    _tickTimer?.cancel();
    _allNotesOff();
    _stateController.close();
    _measureController.close();
  }
}
