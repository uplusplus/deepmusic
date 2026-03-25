import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../score/models/score.dart';
import '../../score/services/musicxml_parser.dart';
import '../services/auto_player.dart';
import '../services/audio_synth_service.dart';

/// 真机播放集成测试页面
///
/// 验证:
/// 1. AudioSynthService 初始化是否正常
/// 2. AutoPlayer 播放计时精度
/// 3. Note On/Off 事件时间与预期的偏差
/// 4. 实际播放时是否有卡顿/丢音
class PlaybackTestPage extends StatefulWidget {
  const PlaybackTestPage({super.key});

  @override
  State<PlaybackTestPage> createState() => _PlaybackTestPageState();
}

class _PlaybackTestPageState extends State<PlaybackTestPage> {
  final List<String> _logs = [];
  final ScrollController _scrollCtrl = ScrollController();
  bool _running = false;
  AutoPlayer? _player;
  Score? _testScore;

  // 计时精度测试数据
  final List<_TimingSample> _timingSamples = [];
  final Stopwatch _realtimeClock = Stopwatch();

  void _log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    setState(() {
      _logs.add('[$ts] $msg');
    });
    debugPrint('[PlaybackTest] $msg');
    // 自动滚到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ──────────────── 测试用例 ────────────────

  Future<void> _runAllTests() async {
    if (_running) return;
    setState(() => _running = true);
    _logs.clear();
    _timingSamples.clear();

    _log('═══════════════════════════════════════════');
    _log('  DeepMusic 播放集成测试');
    _log('═══════════════════════════════════════════');

    await _testAudioSynthInit();
    await _testScoreParsing();
    await _testTimingAccuracy();
    await _testPlaybackRealtime();

    _log('');
    _log('═══════════════════════════════════════════');
    _log('  所有测试完成');
    _log('═══════════════════════════════════════════');

    setState(() => _running = false);
  }

  /// 测试 1: AudioSynthService 初始化
  Future<void> _testAudioSynthInit() async {
    _log('');
    _log('── 测试 1: AudioSynthService 初始化 ──');

    final synth = AudioSynthService();
    _log('  正在加载 SF2 音色文件...');

    try {
      await synth.init();
      if (synth.isInitialized) {
        _log('  ✅ 合成器初始化成功');
        _log('  采样率: 44100Hz, 最大复音数: 64');

        // 测试发声
        synth.noteOn(60, 100); // C4
        _log('  发送 noteOn(C4, velocity=100)...');
        await Future.delayed(const Duration(milliseconds: 500));
        synth.noteOff(60);
        _log('  发送 noteOff(C4)');
        _log('  ✅ 音频输出正常 (如果你听到了 C4 音)');
      } else {
        _log('  ❌ 合成器初始化失败');
      }
    } catch (e) {
      _log('  ❌ 初始化异常: $e');
    }
  }

  /// 测试 2: Score 解析 + tempo 检测
  Future<void> _testScoreParsing() async {
    _log('');
    _log('── 测试 2: Score 解析 & tempo 检测 ──');

    try {
      // 尝试加载本地乐谱文件
      final scoreFiles = [
        'assets/scores/test_score.xml',  // 如果有的话
      ];

      Score? score;
      for (final path in scoreFiles) {
        try {
          final xml = await rootBundle.loadString(path);
          score = MusicXmlParser.parseString(xml, filePath: path);
          break;
        } catch (_) {}
      }

      // 如果没有本地文件，用内嵌的测试 XML
      score ??= _buildTestScore();

      _testScore = score;
      _log('  标题: ${score.title}');
      _log('  作曲: ${score.composer}');
      _log('  tempo: ${score.tempo} BPM');
      _log('  小节数: ${score.totalMeasures}');
      _log('  音符数: ${score.allNotes.length}');
      _log('  预估时长: ${score.formattedDuration}');

      // 验证 tempo 不是默认值 120
      if (score.tempo != 120) {
        _log('  ✅ tempo 检测正确 (${score.tempo} ≠ 默认 120)');
      } else {
        _log('  ⚠️ tempo=120 (可能是默认值或实际就是 120 BPM)');
      }

      // 验证音符 pitch
      if (score.allNotes.isNotEmpty) {
        final first = score.allNotes.first;
        _log('  首音符: ${first.pitch} (MIDI ${first.pitchNumber}) @ ${first.startMs}ms');
        if (first.pitchNumber >= 0 && first.pitchNumber <= 127) {
          _log('  ✅ pitchNumber 在 MIDI 范围内');
        }
      }
    } catch (e) {
      _log('  ❌ 解析失败: $e');
    }
  }

  /// 测试 3: 计时精度
  /// 播放时记录每个事件的 预期时间 vs 实际触发时间
  Future<void> _testTimingAccuracy() async {
    _log('');
    _log('── 测试 3: 事件调度计时精度 ──');

    if (_testScore == null) {
      _log('  ⚠️ 无乐谱，跳过');
      return;
    }

    final player = AutoPlayer(_testScore!);
    _player = player;

    // 等待合成器就绪
    await Future.delayed(const Duration(milliseconds: 500));

    _timingSamples.clear();
    _realtimeClock.reset();
    _realtimeClock.start();

    // 订阅 measureStream 来跟踪事件
    final sub = player.measureStream.listen((measure) {
      final elapsed = _realtimeClock.elapsedMilliseconds;
      _timingSamples.add(_TimingSample(
        expectedMs: 0, // measure stream 不提供精确时间
        actualMs: elapsed,
        label: 'Measure $measure',
      ));
    });

    // 订阅 stateStream 获取 position
    final stateSub = player.stateStream.listen((state) {
      // 每次 state 更新记录一个样本
      final actualMs = _realtimeClock.elapsedMilliseconds;
      _timingSamples.add(_TimingSample(
        expectedMs: state.position.inMilliseconds,
        actualMs: actualMs,
        label: 'pos=${state.position.inMilliseconds}ms',
      ));
    });

    _log('  开始播放 (2x 速, 加速测试)...');
    player.play(rate: 2.0);

    // 等待播放完成或最多 30 秒
    int waited = 0;
    while (player.isPlaying && waited < 30000) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }
    player.stop();
    _realtimeClock.stop();

    sub.cancel();
    stateSub.cancel();

    // 分析计时偏差
    if (_timingSamples.isNotEmpty) {
      final diffs = <int>[];
      for (final s in _timingSamples) {
        if (s.expectedMs > 0) {
          diffs.add((s.actualMs - s.expectedMs).abs());
        }
      }

      if (diffs.isNotEmpty) {
        diffs.sort();
        final avg = diffs.reduce((a, b) => a + b) / diffs.length;
        final median = diffs[diffs.length ~/ 2];
        final max = diffs.last;
        final p95 = diffs[(diffs.length * 0.95).toInt()];

        _log('  采样数: ${diffs.length}');
        _log('  平均偏差: ${avg.toStringAsFixed(1)}ms');
        _log('  中位偏差: ${median}ms');
        _log('  P95 偏差: ${p95}ms');
        _log('  最大偏差: ${max}ms');

        if (max < 50) {
          _log('  ✅ 计时精度优秀 (最大偏差 <50ms)');
        } else if (max < 100) {
          _log('  ⚠️ 计时精度一般 (最大偏差 <100ms)');
        } else {
          _log('  ❌ 计时精度差 (最大偏差 ${max}ms)');
        }
      }
    }

    _player = null;
    player.dispose();
  }

  /// 测试 4: 实时播放完整性
  /// 播放时检测是否有断音/异常
  Future<void> _testPlaybackRealtime() async {
    _log('');
    _log('── 测试 4: 实时播放完整性 ──');

    final score = _buildTestScore();
    final player = AutoPlayer(score);

    await Future.delayed(const Duration(milliseconds: 300));

    // 监听状态变化，检测异常
    int stateEmitCount = 0;
    int measureChangeCount = 0;
    final stateSub = player.stateStream.listen((state) {
      stateEmitCount++;
    });
    final measureSub = player.measureStream.listen((measure) {
      measureChangeCount++;
    });

    _log('  播放 C 大调音阶 (1x 速)...');
    final sw = Stopwatch()..start();
    player.play(rate: 1.0);

    // 等待播放完成
    while (player.isPlaying && sw.elapsedMilliseconds < 15000) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    final totalMs = sw.elapsedMilliseconds;
    sw.stop();

    player.stop();
    stateSub.cancel();
    measureSub.cancel();

    _log('  实际播放时长: ${totalMs}ms');
    _log('  状态更新次数: $stateEmitCount');
    _log('  小节切换次数: $measureChangeCount');

    // 如果状态更新次数合理 (约 33fps × 秒数)，说明节流生效
    final expectedStateEmits = (totalMs / 30).ceil(); // ~33fps
    if (stateEmitCount <= expectedStateEmits * 1.5) {
      _log('  ✅ UI 节流正常 (~${(stateEmitCount * 1000 / totalMs).toStringAsFixed(0)} fps)');
    } else {
      _log('  ⚠️ UI 更新过于频繁 (${stateEmitCount} 次 / ${totalMs}ms)');
    }

    _player = null;
    player.dispose();
  }

  /// 构造测试用 Score: C 大调音阶
  Score _buildTestScore() {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>C Major Scale Test</work-title></work>
  <identification><creator type="composer">Test</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <key><fifths>0</fifths><mode>major</mode></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <direction><sound tempo="100"/></direction>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>B</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration></note>
    </measure>
    <measure number="2">
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration></note>
      <note><pitch><step>B</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>2</duration></note>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note>
    </measure>
  </part>
</score-partwise>
''';
    return MusicXmlParser.parseString(xml);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔨 播放集成测试'),
        actions: [
          if (!_running)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: _runAllTests,
              tooltip: '运行全部测试',
            ),
        ],
      ),
      body: Column(
        children: [
          // 控制栏
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _running ? null : _runAllTests,
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.science),
                  label: Text(_running ? '测试进行中...' : '运行全部测试'),
                ),
                const SizedBox(width: 12),
                if (_player != null && _player!.isPlaying)
                  ElevatedButton.icon(
                    onPressed: () {
                      _player?.stop();
                      setState(() {});
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('停止'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 日志区域
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(12),
              itemCount: _logs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  _logs[i],
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: _logs[i].contains('❌')
                        ? Colors.red
                        : _logs[i].contains('⚠️')
                            ? Colors.orange
                            : _logs[i].contains('✅')
                                ? Colors.green
                                : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimingSample {
  final int expectedMs;
  final int actualMs;
  final String label;
  _TimingSample({required this.expectedMs, required this.actualMs, required this.label});
}
