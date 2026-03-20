import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../midi/services/midi_service.dart';
import '../../score/models/score.dart';
import '../models/note_event.dart';
import '../services/score_follower.dart';
import '../services/note_evaluator.dart';

/// 练习状态
enum PracticeState {
  idle,       // 待开始
  ready,      // MIDI 已连接，等待开始
  playing,    // 练习中
  paused,     // 暂停
  completed,  // 完成
}

class PracticePage extends ConsumerStatefulWidget {
  final String scoreId;
  final Score? score;

  const PracticePage({
    super.key,
    required this.scoreId,
    this.score,
  });

  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<PracticePage> {
  PracticeState _state = PracticeState.idle;
  ScoreFollower? _follower;
  final NoteEvaluator _evaluator = NoteEvaluator();
  final MidiService _midiService = MidiService();
  
  // 练习数据
  PracticeProgress? _progress;
  List<NoteEvaluation> _evaluations = [];
  DateTime? _startTime;
  
  // 流订阅
  StreamSubscription<MidiEvent>? _midiSub;
  StreamSubscription<PracticeProgress>? _progressSub;
  StreamSubscription<MidiConnectionState>? _connectionSub;
  
  // MIDI 连接状态
  MidiConnectionState _connectionState = MidiConnectionState.disconnected;
  String? _connectedDeviceName;

  @override
  void initState() {
    super.initState();
    _initMidiConnection();
  }

  void _initMidiConnection() {
    // 监听连接状态
    _connectionSub = _midiService.connectionState.listen((state) {
      if (mounted) {
        setState(() {
          _connectionState = state;
          _connectedDeviceName = _midiService.connectedDevice?.name;
          if (state == MidiConnectionState.connected) {
            _state = PracticeState.ready;
          } else if (state == MidiConnectionState.disconnected) {
            if (_state == PracticeState.ready) {
              _state = PracticeState.idle;
            }
          }
        });
      }
    });

    // 如果已连接，直接进入 ready
    if (_midiService.currentState == MidiConnectionState.connected) {
      _state = PracticeState.ready;
      _connectedDeviceName = _midiService.connectedDevice?.name;
    }
  }

  void _startPractice() {
    if (widget.score == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('乐谱数据未加载')),
      );
      return;
    }

    setState(() {
      _state = PracticeState.playing;
      _startTime = DateTime.now();
      _evaluations = [];
    });

    // 初始化跟随器
    _follower = ScoreFollower(widget.score!);
    
    // 监听进度
    _progressSub = _follower!.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _progress = progress;
          if (progress.completionPercentage >= 1.0) {
            _state = PracticeState.completed;
            _showReport();
          }
        });
      }
    });

    // 监听 MIDI 事件
    _midiSub = _midiService.midiStream.listen(_onMidiEvent);

    setState(() {});
  }

  void _onMidiEvent(MidiEvent event) {
    if (_state != PracticeState.playing || _follower == null) return;

    // 转换为 NoteEvent
    final noteEvent = NoteEvent(
      noteNumber: event.note,
      velocity: event.velocity,
      timestamp: event.timestamp,
      isNoteOn: event.type == MidiEventType.noteOn,
    );

    if (!noteEvent.isNoteOn) return;

    // 评估
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

    // 推进跟随器
    _follower!.processMidiEvent(noteEvent);
  }

  void _pausePractice() {
    setState(() {
      _state = PracticeState.paused;
    });
    _midiSub?.pause();
  }

  void _resumePractice() {
    setState(() {
      _state = PracticeState.playing;
    });
    _midiSub?.resume();
  }

  void _stopPractice() {
    _midiSub?.cancel();
    _progressSub?.cancel();
    
    if (_evaluations.isNotEmpty) {
      _state = PracticeState.completed;
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
    });
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
    _follower?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_state == PracticeState.playing ? '练习中' : '准备练习'),
        actions: [
          if (_state == PracticeState.playing || _state == PracticeState.paused)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopPractice,
            ),
        ],
      ),
      body: Column(
        children: [
          // MIDI 连接状态
          _buildConnectionBar(),
          
          // 进度条
          if (_progress != null)
            LinearProgressIndicator(
              value: _progress!.completionPercentage,
              backgroundColor: AppColors.divider,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),

          // 乐谱区域
          Expanded(
            flex: 3,
            child: _buildScoreArea(),
          ),

          // 键盘可视化
          _buildKeyboard(),

          // 实时统计 & 控制
          _buildControlPanel(),
        ],
      ),
    );
  }

  Widget _buildConnectionBar() {
    Color color;
    String text;
    IconData icon;

    switch (_connectionState) {
      case MidiConnectionState.connected:
        color = AppColors.success;
        text = '已连接: $_connectedDeviceName';
        icon = Icons.bluetooth_connected;
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
          Text(text, style: TextStyle(color: color, fontSize: 12)),
          const Spacer(),
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
    final expectedNote = _follower?.getCurrentExpectedNote();
    final upcomingNotes = _follower?.getUpcomingNotes(count: 8) ?? [];

    return Container(
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 当前应弹音符
          if (expectedNote != null) ...[
            Text(
              expectedNote.pitch,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '第 ${_follower!.currentMeasure} 小节 · 第 ${_follower!.currentPage}/${_follower!.totalPages} 页',
              style: const TextStyle(color: Colors.grey),
            ),
          ] else ...[
            const Icon(Icons.music_note, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('乐谱跟随区域'),
          ],
          
          const SizedBox(height: 24),
          
          // 接下来的音符预览
          if (upcomingNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: upcomingNotes.map((note) {
                  final isCurrent = note == expectedNote;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrent 
                        ? AppColors.primary 
                        : AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      note.pitch,
                      style: TextStyle(
                        color: isCurrent ? Colors.white : AppColors.primary,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          
          if (_state == PracticeState.ready)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text(
                '按下琴键开始练习',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          
          if (_state == PracticeState.paused)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text(
                '已暂停',
                style: TextStyle(color: AppColors.warning, fontSize: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKeyboard() {
    // 可视化 MIDI 键盘 - 显示 2 个八度
    final currentNote = _follower?.getCurrentExpectedNote();
    final baseOctave = currentNote != null 
      ? (currentNote.pitchNumber ~/ 12) - 1 
      : 4;
    final baseNote = baseOctave * 12; // C of base octave

    return Container(
      height: 100,
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(24, (index) {
            final noteNumber = baseNote + index;
            final isBlack = [1, 3, 6, 8, 10].contains(noteNumber % 12);
            final isExpected = currentNote?.pitchNumber == noteNumber;

            if (isBlack) {
              return Container(
                width: 20,
                height: 60,
                margin: const EdgeInsets.symmetric(horizontal: -10),
                decoration: BoxDecoration(
                  color: isExpected ? AppColors.primary : Colors.black,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(3),
                    bottomRight: Radius.circular(3),
                  ),
                ),
              );
            }

            return Expanded(
              child: Container(
                height: 90,
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                decoration: BoxDecoration(
                  color: isExpected ? AppColors.primaryLight : Colors.white,
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(3),
                    bottomRight: Radius.circular(3),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    final pitchAccuracy = _progress?.pitchAccuracy ?? 1.0;
    final correctNotes = _progress?.correctNotes ?? 0;
    final wrongNotes = _progress?.wrongNotes ?? 0;
    final completion = _progress?.completionPercentage ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 实时统计
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                '音准', 
                '${(pitchAccuracy * 100).toInt()}%',
                pitchAccuracy > 0.8 ? AppColors.success : AppColors.error,
              ),
              _buildStatItem('正确', '$correctNotes', AppColors.success),
              _buildStatItem('错误', '$wrongNotes', wrongNotes > 0 ? AppColors.error : AppColors.textSecondary),
              _buildStatItem('完成', '${(completion * 100).toInt()}%', AppColors.info),
            ],
          ),
          const SizedBox(height: 16),

          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: _follower != null 
                  ? () => _follower!.jumpToMeasure(1) 
                  : null,
                iconSize: 32,
              ),
              _buildMainButton(),
              IconButton(
                icon: const Icon(Icons.replay),
                onPressed: _resetPractice,
                iconSize: 32,
              ),
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
          icon: const Icon(Icons.bluetooth_disabled),
          label: const Text('请先连接 MIDI'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        );
      case PracticeState.ready:
        return ElevatedButton.icon(
          onPressed: _startPractice,
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始练习'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            backgroundColor: AppColors.primary,
          ),
        );
      case PracticeState.playing:
        return ElevatedButton.icon(
          onPressed: _pausePractice,
          icon: const Icon(Icons.pause),
          label: const Text('暂停'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            backgroundColor: AppColors.warning,
          ),
        );
      case PracticeState.paused:
        return ElevatedButton.icon(
          onPressed: _resumePractice,
          icon: const Icon(Icons.play_arrow),
          label: const Text('继续'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            backgroundColor: AppColors.primary,
          ),
        );
      case PracticeState.completed:
        return ElevatedButton.icon(
          onPressed: _showReport,
          icon: const Icon(Icons.assessment),
          label: const Text('查看报告'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            backgroundColor: AppColors.info,
          ),
        );
    }
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildReportSheet(PracticeReport report) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
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
              // 标题
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          report.grade,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '综合评分: ${report.overallScore.toInt()}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.formattedDuration,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 详细分数
              _buildScoreRow('音准', report.pitchScore),
              const SizedBox(height: 12),
              _buildScoreRow('节奏', report.rhythmScore),
              const SizedBox(height: 24),

              // 统计
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildReportStat('总音符', report.totalNotes.toString()),
                  _buildReportStat('正确', report.correctNotes.toString()),
                  _buildReportStat('错误', report.wrongNotes.toString()),
                  _buildReportStat('遗漏', report.missedNotes.toString()),
                ],
              ),
              const SizedBox(height: 32),

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _resetPractice();
                      },
                      child: const Text('再来一次'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('返回'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScoreRow(String label, double score) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('${score.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            minHeight: 8,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation(
              score >= 80 ? AppColors.success 
                : score >= 60 ? AppColors.warning 
                : AppColors.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}
