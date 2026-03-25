import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// 内置音频合成服务
///
/// 使用 dart_melty_soundfont + flutter_pcm_sound 实现软件钢琴合成。
/// 当没有物理 MIDI 设备连接时，作为 fallback 输出音频。
///
/// 使用方式:
/// 1. init() — 加载 SF2 音色文件，初始化音频输出
/// 2. noteOn(note, velocity) / noteOff(note) — 触发/释放音符
/// 3. dispose() — 释放资源
class AudioSynthService {
  static final AudioSynthService _instance = AudioSynthService._internal();
  factory AudioSynthService() => _instance;
  AudioSynthService._internal();

  Synthesizer? _synth;
  bool _isInitialized = false;
  bool _isFeeding = false;

  // PCM 渲染参数
  static const int _sampleRate = 44100;
  static const int _blockSize = 256; // 每次渲染的采样数 (~5.8ms @ 44100Hz)
  static const int _feedThreshold = 512; // 触发 feed 回调的阈值

  // 渲染缓冲区
  ArrayInt16? _renderBuf;
  // 预分配的 PCM 数据缓冲区，避免每次 feed 都 new ByteData
  PcmArrayInt16? _pcmBuf;

  // 音量增益 (0.0-1.0)，在 PCM 渲染时应用
  double _volume = 1.0;

  bool get isInitialized => _isInitialized;

  /// 当前音量增益 (0.0-1.0)
  double get volume => _volume;

  /// 设置音量增益 (0.0-1.0)
  /// 在 PCM 渲染阶段直接缩放采样值
  set volume(double v) {
    _volume = v.clamp(0.0, 1.0);
  }

  /// 初始化合成器
  ///
  /// [sf2AssetPath] SF2 音色文件的 asset 路径，默认 'assets/sf2/Piano.sf2'
  Future<void> init({String sf2AssetPath = 'assets/sf2/Piano.sf2'}) async {
    if (_isInitialized) return;

    try {
      // 加载 SF2 文件
      debugPrint('[AudioSynth] Loading SF2: $sf2AssetPath');
      final bytes = await rootBundle.load(sf2AssetPath);

      // 创建合成器
      _synth = Synthesizer.loadByteData(
        bytes,
        SynthesizerSettings(
          sampleRate: _sampleRate,
          blockSize: 64,
          maximumPolyphony: 64,
          enableReverbAndChorus: true,
        ),
      );

      // 选择钢琴音色 (preset 0 通常是 Acoustic Grand Piano)
      _synth!.selectPreset(channel: 0, preset: 0);

      // 初始化 PCM 缓冲区
      _renderBuf = ArrayInt16.zeros(numShorts: _blockSize);
      // 预分配 PcmArrayInt16，避免 feed 时重复分配
      _pcmBuf = PcmArrayInt16(bytes: ByteData(_blockSize * 2));

      // 初始化 flutter_pcm_sound (mono 输出)
      FlutterPcmSound.setLogLevel(LogLevel.error);
      await FlutterPcmSound.setup(
        sampleRate: _sampleRate,
        channelCount: 1,
      );
      await FlutterPcmSound.setFeedThreshold(_feedThreshold);
      FlutterPcmSound.setFeedCallback(_onFeed);

      _isInitialized = true;
      debugPrint('[AudioSynth] Initialized: ${_sampleRate}Hz, polyphony=64');
    } catch (e) {
      debugPrint('[AudioSynth] Init failed: $e');
      _isInitialized = false;
    }
  }

  /// PCM feed 回调 — flutter_pcm_sound 需要更多数据时调用
  ///
  /// 🔑 优化: 预分配缓冲区 + 减少 async 平台调用次数
  /// 此前问题: 每个 block 做 512 次单字节拷贝 + 循环中频繁 await platform call
  void _onFeed(int remainingFrames) async {
    if (!_isInitialized || _synth == null || _renderBuf == null || _pcmBuf == null) return;

    // 批量渲染: 一次喂 4 个 block (~23ms 音频)，减少 platform call 频率
    const int blocksPerFeed = 4;

    for (int b = 0; b < blocksPerFeed; b++) {
      final remaining = await FlutterPcmSound.remainingFrames();
      if (remaining > _feedThreshold * 2) break;

      // 渲染一个 block 的 mono PCM
      _synth!.renderMonoInt16(_renderBuf!);

      // 应用音量增益（在采样层面缩放）
      // ArrayInt16.bytes 是 ByteData，用 ArrayInt16 的 [] / []= 操作符读写
      if (_volume < 1.0) {
        for (int i = 0; i < _blockSize; i++) {
          final sample = _renderBuf![i]; // 通过 ArrayInt16.operator[] 读取
          _renderBuf![i] = (sample * _volume).round().clamp(-32768, 32767);
        }
      }

      // 🔑 直接引用 ByteData 内存，零拷贝传给 PcmArrayInt16
      final srcBytes = _renderBuf!.bytes; // ByteData
      await FlutterPcmSound.feed(PcmArrayInt16(bytes: srcBytes));
    }
  }

  /// 触发音符
  void noteOn(int note, int velocity) {
    if (!_isInitialized || _synth == null) return;
    _synth!.noteOn(channel: 0, key: note.clamp(0, 127), velocity: velocity.clamp(0, 127));
    _ensureFeeding();
  }

  /// 释放音符
  void noteOff(int note) {
    if (!_isInitialized || _synth == null) return;
    _synth!.noteOff(channel: 0, key: note.clamp(0, 127));
  }

  /// 释放所有音符
  void allNotesOff() {
    if (!_isInitialized || _synth == null) return;
    for (int i = 0; i < 128; i++) {
      _synth!.noteOff(channel: 0, key: i);
    }
  }

  /// 确保 PCM feed 循环在运行
  void _ensureFeeding() {
    if (_isFeeding) return;
    _isFeeding = true;
    FlutterPcmSound.play();
  }

  /// 暂停音频输出
  void pause() {
    FlutterPcmSound.pause();
    _isFeeding = false;
  }

  /// 恢复音频输出
  void resume() {
    _ensureFeeding();
  }

  /// 停止并重置
  void stop() {
    allNotesOff();
    FlutterPcmSound.stop();
    _isFeeding = false;
  }

  /// 设置乐器
  ///
  /// [preset] 预设编号 (0=Acoustic Grand Piano, 1=Bright Piano, etc.)
  void setInstrument(int preset) {
    if (!_isInitialized || _synth == null) return;
    _synth!.selectPreset(channel: 0, preset: preset);
  }

  void dispose() {
    stop();
    _synth = null;
    _renderBuf = null;
    _pcmBuf = null;
    _isInitialized = false;
  }
}
