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

  bool get isInitialized => _isInitialized;

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
  void _onFeed(int remainingFrames) async {
    if (!_isInitialized || _synth == null || _renderBuf == null) return;

    // 持续喂数据直到缓冲区足够
    while (true) {
      final remaining = await FlutterPcmSound.remainingFrames();
      if (remaining > _feedThreshold * 2) break;

      // 渲染一个 block 的 mono PCM
      _synth!.renderMonoInt16(_renderBuf!);

      // ArrayInt16 → PcmArrayInt16 (复制 bytes)
      final src = _renderBuf!.bytes;
      final dst = ByteData(src.lengthInBytes);
      for (int i = 0; i < src.lengthInBytes; i++) {
        dst.setUint8(i, src.getUint8(i));
      }
      await FlutterPcmSound.feed(PcmArrayInt16(bytes: dst));
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
    _isInitialized = false;
  }
}
