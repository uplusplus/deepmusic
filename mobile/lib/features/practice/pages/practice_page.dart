import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/score_repository.dart';
import '../../midi/services/midi_service.dart';
import '../../score/models/score.dart';
import '../../score/services/musicxml_parser.dart';
import '../../score/widgets/score_renderer.dart';
import '../models/note_event.dart';
import '../services/score_follower.dart';
import '../services/note_evaluator.dart';
import '../widgets/piano_keyboard.dart';

enum PracticeState { idle, ready, playing, paused, completed }

class PracticePage extends ConsumerStatefulWidget {
  final String scoreId;
  final Score? score;

  const PracticePage({super.key, required this.scoreId, this.score});

  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<PracticePage> {
  PracticeState _state = PracticeState.idle;
  ScoreFollower? _follower;
  final NoteEvaluator _evaluator = NoteEvaluator();
  final MidiService _midiService = MidiService();
  final ScoreRepository _scoreRepo = ScoreRepository();

  PracticeProgress? _progress;
  List<NoteEvaluation> _evaluations = [];
  DateTime? _startTime;

  StreamSubscription<MidiEvent>? _midiSub;
  StreamSubscription<PracticeProgress>? _progressSub;
  StreamSubscription<MidiConnectionState>? _connectionSub;

  MidiConnectionState _connectionState = MidiConnectionState.disconnected;
  String? _connectedDeviceName;
  MidiConnectionType? _connectionType;

  // 从 MusicXML 解析的 Score (用于 ScoreFollower)
  Score? _parsedScore;

  // OSMD 渲染
  String? _xmlContent;
  bool _isLoadingXml = true;
  String? _xmlError;
  int _highlightMeasure = 1;
  ScoreRenderInfo? _renderInfo;

  // 循环练习
  bool _loopEnabled = false;
  int _loopStartMeasure = 1;
  int _loopEndMeasure = 4;
  int _loopCycle = 0;
  double? _loopBestScore;

  @override
  void initState() {
    super.initState();
    _initMidiConnection();
    _loadScoreXml();

    // 兜底：首帧后再检查一次连接状态（防止 stream 竞争导致同步检查遗漏）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_midiService.currentState == MidiConnectionState.connected &&
          _connectionState != MidiConnectionState.connected) {
        debugPrint('[PracticePage] Post-frame fix: sync connected state');
        setState(() {
          _connectionState = MidiConnectionState.connected;
          _connectedDeviceName = _midiService.connectedDevice?.name;
          _connectionType = _midiService.connectionType;
          if (_state == PracticeState.idle) {
            _state = PracticeState.ready;
            _startReadyListener();
          }
        });
      }
    });
  }

  void _initMidiConnection() {
    debugPrint('[PracticePage] initState: MidiService.currentState=${_midiService.currentState}, device=${_midiService.connectedDevice?.name}');

    _connectionSub = _midiService.connectionState.listen((state) {
      debugPrint('[PracticePage] stream event: $state, device=${_midiService.connectedDevice?.name}');
      if (mounted) {
        setState(() {
          _connectionState = state;
          _connectedDeviceName = _midiService.connectedDevice?.name;
          _connectionType = _midiService.connectionType;
          if (state == MidiConnectionState.connected) {
            _state = PracticeState.ready;
            _startReadyListener();
          } else if (state == MidiConnectionState.disconnected) {
            if (_state == PracticeState.ready) _state = PracticeState.idle;
            _readyMidiSub?.cancel();
          }
        });
      }
    });

    if (_midiService.currentState == MidiConnectionState.connected) {
      debugPrint('[PracticePage] sync check: connected, setting ready');
      _state = PracticeState.ready;
      _connectionState = MidiConnectionState.connected;  // ← 修复：必须同步设置
      _connectedDeviceName = _midiService.connectedDevice?.name;
      _connectionType = _midiService.connectionType;
      _startReadyListener();
    } else {
      debugPrint('[PracticePage] sync check: not connected (${_midiService.currentState})');
    }
  }

  /// Ready 状态下监听 MIDI 按键，自动开始练习
  StreamSubscription<MidiEvent>? _readyMidiSub;

  void _startReadyListener() {
    _readyMidiSub?.cancel();
    _readyMidiSub = _midiService.midiStream.listen((event) {
      if (_state == PracticeState.ready &&
          event.type == MidiEventType.noteOn &&
          event.velocity > 0) {
        _readyMidiSub?.cancel();
        _startPractice();
      }
    });
  }

  Future<void> _loadScoreXml() async {
    setState(() {
      _isLoadingXml = true;
      _xmlError = null;
    });
    try {
      final xml = await _scoreRepo.getScoreXml(widget.scoreId);
      // 同时解析为 Score 对象
      final score = MusicXmlParser.parseString(xml, scoreId: widget.scoreId);
      if (mounted) setState(() {
        _xmlContent = xml;
        _parsedScore = score;
        _isLoadingXml = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _xmlError = e.toString();
        _isLoadingXml = false;
      });
    }
  }

  void _startPractice() {
    final score = _parsedScore ?? widget.score;
    if (score == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('乐谱数据未加载，请稍候...')),
      );
      return;
    }

    setState(() {
      _state = PracticeState.playing;
      _startTime = DateTime.now();
      _evaluations = [];
      _highlightMeasure = 1;
    });

    _follower = ScoreFollower(score);
    if (_loopEnabled) {
      _follower!.setLoopRange(_loopStartMeasure, _loopEndMeasure);
    }

    _progressSub = _follower!.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _progress = progress;
          _highlightMeasure = progress.currentMeasure;
          if (progress.loopEnabled) {
            _loopCycle = progress.loopCycle;
            _loopBestScore = progress.loopBestScore;
          }
          if (progress.completionPercentage >= 1.0) {
            _state = PracticeState.completed;
            _showReport();
          }
        });
      }
    });

    _midiSub?.cancel();
    _midiSub = _midiService.midiStream.listen(_onMidiEvent);
    setState(() {});
  }

  void _onMidiEvent(MidiEvent event) {
    if (_state != PracticeState.playing || _follower == null) return;

    final noteEvent = NoteEvent(
      noteNumber: event.note,
      velocity: event.velocity,
      timestamp: event.timestamp,
      isNoteOn: event.type == MidiEventType.noteOn,
    );

    if (!noteEvent.isNoteOn) return;

    final expectedNote = _follower!.getCurrentExpectedNote();
    if (expectedNote != null) {
      final expectedStartMs = expectedNote.startMs;
      final playedStartMs = event.timestamp.difference(_startTime!).inMilliseconds;

      final evaluation = _evaluator.evaluate(
        expected: expectedNote,
        played: noteEvent,
        expectedStartTimeMs: expectedStartMs,
        playedStartTimeMs: playedStartMs,
      );
      _evaluations.add(evaluation);
    }

    _follower!.processMidiEvent(noteEvent);
  }

  void _pausePractice() {
    setState(() => _state = PracticeState.paused);
    _midiSub?.pause();
  }

  void _resumePractice() {
    setState(() => _state = PracticeState.playing);
    _midiSub?.resume();
  }

  void _stopPractice() {
    _midiSub?.cancel();
    _progressSub?.cancel();

    if (_evaluations.isNotEmpty) {
      setState(() => _state = PracticeState.completed);
      _showReport();
    } else {
      setState(() {
        _state = PracticeState.ready;
        _follower = null;
        _progress = null;
      });
    }
  }

  void _resetPractice() {
    _midiSub?.cancel();
    _progressSub?.cancel();
    _follower?.reset();

    setState(() {
      _state = PracticeState.ready;
      _follower = null;
      _progress = null;
      _evaluations = [];
      _startTime = null;
      _highlightMeasure = 1;
    });
  }

  // ── 手动翻页 ──

  void _onPageSwipe(DragEndDetails details) {
    if (_follower == null) return;
    final velocity = details.primaryVelocity ?? 0;
    const threshold = 300.0;

    if (velocity < -threshold) {
      // 向左滑 → 下一页
      final nextPage = _follower!.currentPage + 1;
      if (nextPage <= _follower!.totalPages) {
        _follower!.jumpToPage(nextPage);
        setState(() {
          _highlightMeasure = _follower!.currentMeasure;
        });
      }
    } else if (velocity > threshold) {
      // 向右滑 → 上一页
      final prevPage = _follower!.currentPage - 1;
      if (prevPage >= 1) {
        _follower!.jumpToPage(prevPage);
        setState(() {
          _highlightMeasure = _follower!.currentMeasure;
        });
      }
    }
  }

  void _showReport() {
    if (_startTime == null) return;

    final report = _evaluator.generateReport(
      scoreId: widget.scoreId,
      startTime: _startTime!,
      endTime: DateTime.now(),
      evaluations: _evaluations,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildReportSheet(report),
    );
  }

  @override
  void dispose() {
    _midiSub?.cancel();
    _progressSub?.cancel();
    _connectionSub?.cancel();
    _readyMidiSub?.cancel();
    _follower?.dispose();
    super.dispose();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: Text(_state == PracticeState.playing ? '练习中' : '准备练习'),
        actions: [
          if (_state == PracticeState.playing || _state == PracticeState.paused)
            IconButton(icon: const Icon(Icons.stop), onPressed: _stopPractice),
        ],
      ),
      body: isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
    );
  }

  /// 竖屏布局
  Widget _buildPortraitLayout() {
    return Column(
      children: [
        _buildConnectionBar(),
        if (_progress != null)
          LinearProgressIndicator(
            value: _progress!.completionPercentage,
            backgroundColor: AppColors.divider,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        Expanded(flex: 5, child: _buildScoreArea()),
        _buildCurrentNoteBar(),
        PianoKeyboard(
          expectedPitches: _follower?.getCurrentExpectedGroup()?.expectedPitchNumbers ?? {},
          height: 100,
        ),
        _buildControlPanel(),
      ],
    );
  }

  /// 横屏布局 — 乐谱左 | 音符+键盘+控制右
  Widget _buildLandscapeLayout() {
    return Column(
      children: [
        // 上: 乐谱 (占满宽度)
        Expanded(
          child: Column(
            children: [
              _buildConnectionBar(),
              if (_progress != null)
                LinearProgressIndicator(
                  value: _progress!.completionPercentage,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              Expanded(child: _buildScoreArea()),
            ],
          ),
        ),
        // 下: 键盘左 + 当前音符/控制右
        Container(
          height: 140,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              // 键盘 — 占主要宽度
              Expanded(
                child: PianoKeyboard(
                  expectedPitches: _follower?.getCurrentExpectedGroup()?.expectedPitchNumbers ?? {},
                  height: 140,
                ),
              ),
              // 右侧: 当前音符 + 控制面板
              Container(
                width: 280,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: AppColors.divider)),
                ),
                child: Column(
                  children: [
                    _buildCurrentNoteBar(),
                    Expanded(child: _buildControlPanel()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionBar() {
    Color color;
    String text;
    IconData icon;

    switch (_connectionState) {
      case MidiConnectionState.connected:
        color = AppColors.success;
        final typeLabel = _connectionType == MidiConnectionType.usb ? 'USB' : 'BLE';
        text = '已连接 ($typeLabel): $_connectedDeviceName';
        icon = _connectionType == MidiConnectionType.usb
            ? Icons.usb : Icons.bluetooth_connected;
        break;
      case MidiConnectionState.connecting:
      case MidiConnectionState.scanning:
        color = AppColors.warning;
        text = '连接中...';
        icon = Icons.bluetooth_searching;
        break;
      default:
        color = AppColors.error;
        text = '未连接 MIDI 设备';
        icon = Icons.bluetooth_disabled;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withOpacity(0.1),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12))),
          if (_connectionState != MidiConnectionState.connected)
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/devices'),
              child: const Text('连接设备', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreArea() {
    // ★ 核心: OSMD 乐谱渲染 + 手势翻页
    if (_isLoadingXml) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(strokeWidth: 2),
          SizedBox(height: 12),
          Text('加载乐谱...', style: TextStyle(color: Colors.grey)),
        ]),
      );
    }

    if (_xmlError != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(_xmlError!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadScoreXml,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ]),
      );
    }

    if (_xmlContent == null || _xmlContent!.isEmpty) {
      return const Center(
        child: Text('乐谱文件为空', style: TextStyle(color: Colors.grey)),
      );
    }

    // OSMD WebView + 手势翻页
    return GestureDetector(
      onHorizontalDragEnd: _onPageSwipe,
      child: Stack(
        children: [
          ScoreRenderer(
            musicXml: _xmlContent!,
            highlightMeasure: _state == PracticeState.playing ? _highlightMeasure : null,
            loopStartMeasure: _loopEnabled ? _loopStartMeasure : null,
            loopEndMeasure: _loopEnabled ? _loopEndMeasure : null,
            onRendered: (info) {
              setState(() => _renderInfo = info);
            },
            onError: (error) {
              debugPrint('Score render error: $error');
            },
          ),

          // 页码指示器
          if (_follower != null)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '第 ${_follower!.currentPage} / ${_follower!.totalPages} 页  ·  第 $_highlightMeasure 小节',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),

          // 准备状态提示
          if (_state == PracticeState.ready || _state == PracticeState.idle)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _state == PracticeState.ready ? Icons.play_circle : Icons.bluetooth_disabled,
                          size: 48,
                          color: _state == PracticeState.ready ? AppColors.primary : Colors.grey,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _state == PracticeState.ready ? '按下琴键或点击开始' : '请先连接 MIDI 设备',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentNoteBar() {
    final currentGroup = _follower?.getCurrentExpectedGroup();
    final isChord = currentGroup?.isChord ?? false;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          // 当前应弹音符
          if (currentGroup != null) ...[
            if (isChord)
              ...currentGroup.notes.map((n) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(n.pitch,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ))
            else
              Text(currentGroup.notes.first.pitch,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary)),
            if (isChord)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('和弦', style: TextStyle(fontSize: 10, color: AppColors.primary)),
              ),
          ] else
            const Text('—', style: TextStyle(fontSize: 24, color: Colors.grey)),

          const Spacer(),

          // 接下来音符
          if (_follower != null)
            Text(
              '→ ${_follower!.getUpcomingNotes(count: 3).map((n) => n.pitch).join('  ')}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
        ],
      ),
    );
  }


  Widget _buildControlPanel() {
    final pitchAccuracy = _progress?.pitchAccuracy ?? 1.0;
    final correctNotes = _progress?.correctNotes ?? 0;
    final wrongNotes = _progress?.wrongNotes ?? 0;
    final missedNotes = _progress?.missedNotes ?? 0;
    final completion = _progress?.completionPercentage ?? 0;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    return Container(
      padding: EdgeInsets.all(isLandscape ? 8 : 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem('音准', '${(pitchAccuracy * 100).toInt()}%',
                  pitchAccuracy > 0.8 ? AppColors.success : AppColors.error),
              _buildStatItem('正确', '$correctNotes', AppColors.success),
              _buildStatItem('错误', '$wrongNotes',
                  wrongNotes > 0 ? AppColors.error : AppColors.textSecondary),
              if (!isLandscape)
                _buildStatItem('遗漏', '$missedNotes',
                    missedNotes > 0 ? AppColors.warning : AppColors.textSecondary),
              _buildStatItem('完成', '${(completion * 100).toInt()}%', AppColors.info),
            ],
          ),
          const SizedBox(height: 12),
          // 循环控制栏
          _buildLoopControls(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: _follower != null ? () => _follower!.jumpToMeasure(1) : null,
                iconSize: 28,
              ),
              _buildMainButton(),
              IconButton(icon: const Icon(Icons.replay), onPressed: _resetPractice, iconSize: 28),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainButton() {
    switch (_state) {
      case PracticeState.idle:
        return ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.bluetooth_disabled, size: 18),
          label: const Text('请先连接 MIDI'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
        );
      case PracticeState.ready:
        return ElevatedButton.icon(
          onPressed: _startPractice,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('开始练习'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            backgroundColor: AppColors.primary),
        );
      case PracticeState.playing:
        return ElevatedButton.icon(
          onPressed: _pausePractice,
          icon: const Icon(Icons.pause, size: 18),
          label: const Text('暂停'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            backgroundColor: AppColors.warning),
        );
      case PracticeState.paused:
        return ElevatedButton.icon(
          onPressed: _resumePractice,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('继续'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            backgroundColor: AppColors.primary),
        );
      case PracticeState.completed:
        return ElevatedButton.icon(
          onPressed: _showReport,
          icon: const Icon(Icons.assessment, size: 18),
          label: const Text('查看报告'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            backgroundColor: AppColors.info),
        );
    }
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
    ]);
  }

  Widget _buildLoopControls() {
    if (_follower == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _loopEnabled ? Colors.amber.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: _loopEnabled ? Border.all(color: Colors.amber.withOpacity(0.3)) : null,
      ),
      child: Row(
        children: [
          // 循环开关
          SizedBox(
            height: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.repeat, size: 16, color: _loopEnabled ? Colors.amber[700] : Colors.grey),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _loopEnabled,
                    onChanged: (_state == PracticeState.playing || _state == PracticeState.paused)
                        ? null // 练习中不能切换
                        : (v) {
                            setState(() {
                              _loopEnabled = v;
                              if (v && _follower != null) {
                                _follower!.setLoopRange(_loopStartMeasure, _loopEndMeasure);
                              } else if (_follower != null) {
                                _follower!.clearLoopRange();
                              }
                            });
                          },
                    activeColor: Colors.amber[700],
                  ),
                ),
              ],
            ),
          ),

          if (_loopEnabled) ...[
            // 区间显示 + 编辑
            GestureDetector(
              onTap: (_state != PracticeState.playing && _state != PracticeState.paused)
                  ? _showLoopRangePicker
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '[$_loopStartMeasure - $_loopEndMeasure]',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber[800],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 循环次数
            Text(
              '第 ${_loopCycle + 1} 次',
              style: TextStyle(fontSize: 12, color: Colors.amber[800]),
            ),

            // 最佳成绩
            if (_loopBestScore != null) ...[
              const SizedBox(width: 8),
              Text(
                '最佳 ${( _loopBestScore! * 100).toInt()}%',
                style: TextStyle(fontSize: 11, color: Colors.amber[600]),
              ),
            ],
          ] else
            const Text(
              '循环练习',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),

          const Spacer(),

          // 循环趋势按钮
          if (_loopEnabled && _loopCycle > 0)
            IconButton(
              icon: const Icon(Icons.show_chart, size: 18),
              onPressed: _showLoopTrend,
              tooltip: '循环趋势',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  void _showLoopRangePicker() {
    final totalMeasures = widget.score?.totalMeasures ?? 32;
    showModalBottomSheet(
      context: context,
      builder: (context) {
        int tempStart = _loopStartMeasure;
        int tempEnd = _loopEndMeasure;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择循环区间', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Text('起始小节: '),
                      Expanded(
                        child: Slider(
                          value: tempStart.toDouble(),
                          min: 1,
                          max: totalMeasures.toDouble(),
                          divisions: totalMeasures - 1,
                          label: '$tempStart',
                          onChanged: (v) => setModalState(() {
                            tempStart = v.round();
                            if (tempStart > tempEnd) tempEnd = tempStart;
                          }),
                        ),
                      ),
                      SizedBox(width: 40, child: Text('$tempStart', textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('结束小节: '),
                      Expanded(
                        child: Slider(
                          value: tempEnd.toDouble(),
                          min: 1,
                          max: totalMeasures.toDouble(),
                          divisions: totalMeasures - 1,
                          label: '$tempEnd',
                          onChanged: (v) => setModalState(() {
                            tempEnd = v.round();
                            if (tempEnd < tempStart) tempStart = tempEnd;
                          }),
                        ),
                      ),
                      SizedBox(width: 40, child: Text('$tempEnd', textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _loopStartMeasure = tempStart;
                          _loopEndMeasure = tempEnd;
                          if (_follower != null) {
                            _follower!.setLoopRange(tempStart, tempEnd);
                          }
                        });
                        Navigator.pop(context);
                      },
                      child: Text('确认 ($tempStart - $tempEnd)'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showLoopTrend() {
    final scores = _follower != null
        ? (List.generate(_loopCycle, (i) => (i + 1).toString()))
        : <String>[];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('循环趋势'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('共 $_loopCycle 次循环'),
            if (_loopBestScore != null)
              Text('最佳成绩: ${(_loopBestScore! * 100).toInt()}%',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _buildReportSheet(PracticeReport report) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: Column(children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                  child: Center(child: Text(report.grade,
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary))),
                ),
                const SizedBox(height: 12),
                Text('综合评分: ${report.overallScore.toInt()}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                Text(report.formattedDuration, style: const TextStyle(color: Colors.grey)),
              ])),
              const SizedBox(height: 24),
              _buildScoreRow('音准', report.pitchScore),
              const SizedBox(height: 12),
              _buildScoreRow('节奏', report.rhythmScore),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _buildReportStat('总音符', report.totalNotes.toString()),
                _buildReportStat('正确', report.correctNotes.toString()),
                _buildReportStat('错误', report.wrongNotes.toString()),
                _buildReportStat('遗漏', report.missedNotes.toString()),
              ]),
              const SizedBox(height: 32),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () { Navigator.pop(context); _resetPractice(); },
                  child: const Text('再来一次'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('返回'),
                )),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScoreRow(String label, double score) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Text('${score.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
        value: score / 100, minHeight: 8, backgroundColor: Colors.grey[200],
        valueColor: AlwaysStoppedAnimation(
          score >= 80 ? AppColors.success : score >= 60 ? AppColors.warning : AppColors.error),
      )),
    ]);
  }

  Widget _buildReportStat(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ]);
  }
}
