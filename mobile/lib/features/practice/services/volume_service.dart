import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../settings/services/app_settings.dart';
import '../../midi/services/midi_service.dart';

/// 音量控制服务
///
/// 统一管理本机音量和 MIDI 音量：
/// - 本机模式: 音量键直接控制系统媒体音量（系统自动处理），UI 滑块调整合成器增益
/// - MIDI 模式: UI 滑块 + 音量键 → MIDI CC#7 (Volume)
///
/// 每个输出模式独立存储音量偏好。
class VolumeService {
  static final VolumeService _instance = VolumeService._internal();
  factory VolumeService() => _instance;
  VolumeService._internal();

  final MidiService _midiService = MidiService();
  final AppSettings _settings = AppSettings();

  // 各模式的音量 (0.0 - 1.0)
  double _localVolume = 1.0;   // 本机合成器增益
  double _midiVolume = 0.78;   // MIDI CC#7 (对应 ~100/127)

  // MIDI 音量上限 (MIDI CC#7 范围 0-127)
  int get _midiVolumeCc => (_midiVolume * 127).round().clamp(0, 127);

  final _volumeController = StreamController<double>.broadcast();

  /// 音量变化流 (当前模式的音量, 0.0-1.0)
  Stream<double> get volumeStream => _volumeController.stream;

  /// 当前模式的音量 (0.0-1.0)
  double get volume {
    return _settings.audioOutputMode == AudioOutputMode.midi
        ? _midiVolume
        : _localVolume;
  }

  /// 本机模式增益 (0.0-1.0)
  double get localVolume => _localVolume;

  /// MIDI 模式音量 (0.0-1.0)
  double get midiVolume => _midiVolume;

  /// MIDI CC#7 值 (0-127)
  int get midiVolumeCc => _midiVolumeCc;

  /// 当前是否 MIDI 输出模式
  bool get isMidiMode => _settings.audioOutputMode == AudioOutputMode.midi;

  /// 初始化，从本地存储加载
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _localVolume = prefs.getDouble('volume_local') ?? 1.0;
      _midiVolume = prefs.getDouble('volume_midi') ?? 0.78;
      debugPrint('[VolumeService] Loaded: local=$_localVolume, midi=$_midiVolume');
    } catch (e) {
      debugPrint('[VolumeService] Load failed: $e');
    }

    // 如果当前是 MIDI 模式且有设备连接，同步音量
    if (isMidiMode && _midiService.connectedDevice != null) {
      _sendMidiVolume();
    }
  }

  /// 设置当前模式的音量
  ///
  /// [v] 音量值 0.0-1.0
  Future<void> setVolume(double v) async {
    v = v.clamp(0.0, 1.0);
    debugPrint('[VolumeService] setVolume($v), mode=${isMidiMode ? "MIDI" : "LOCAL"}');

    if (isMidiMode) {
      _midiVolume = v;
      _sendMidiVolume();
    } else {
      _localVolume = v;
      // 本机模式的合成器增益由 AudioSynthService 读取 localVolume
    }

    _volumeController.add(v);
    await _persist();
  }

  /// 增减音量（音量键触发）
  ///
  /// [delta] 步长，正数增大，负数减小
  Future<void> adjustVolume(double delta) async {
    final current = volume;
    final next = (current + delta).clamp(0.0, 1.0);
    await setVolume(next);
  }

  /// 输出模式切换时调用，同步音量到新模式
  void onOutputModeChanged() {
    _volumeController.add(volume);
    if (isMidiMode && _midiService.connectedDevice != null) {
      _sendMidiVolume();
    }
  }

  /// MIDI 设备连接时调用，发送当前音量
  void onMidiDeviceConnected() {
    if (isMidiMode) {
      _sendMidiVolume();
    }
  }

  /// 发送 MIDI CC#7
  void _sendMidiVolume() {
    final device = _midiService.connectedDevice;
    if (device == null) {
      debugPrint('[VolumeService] ⚠️ No MIDI device, skip CC#7');
      return;
    }
    final cc = _midiVolumeCc;
    debugPrint('[VolumeService] → MIDI CC#7=$cc, device=${device.name}, type=${_midiService.connectionType}');
    _midiService.sendControlChange(7, cc);
  }

  /// 持久化
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('volume_local', _localVolume);
      await prefs.setDouble('volume_midi', _midiVolume);
    } catch (e) {
      debugPrint('[VolumeService] Persist failed: $e');
    }
  }

  void dispose() {
    _volumeController.close();
  }
}
