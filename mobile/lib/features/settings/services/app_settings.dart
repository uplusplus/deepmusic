import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 音频输出模式
enum AudioOutputMode {
  /// 通过连接的 MIDI 设备输出音频
  midi,

  /// 通过本机内置合成器输出音频
  local,
}

/// 应用设置服务
///
/// 使用 SharedPreferences 持久化用户偏好设置。
/// 单例模式，全局可访问。
class AppSettings {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  static const _keyAudioOutput = 'audio_output_mode';
  static const _keyShowKeyboard = 'show_keyboard_default';

  AudioOutputMode _audioOutputMode = AudioOutputMode.local;
  bool _showKeyboardDefault = true;
  bool _loaded = false;

  AudioOutputMode get audioOutputMode => _audioOutputMode;
  bool get showKeyboardDefault => _showKeyboardDefault;

  /// 初始化：从本地存储加载设置
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      final audioIndex = prefs.getInt(_keyAudioOutput);
      if (audioIndex != null && audioIndex < AudioOutputMode.values.length) {
        _audioOutputMode = AudioOutputMode.values[audioIndex];
      }

      _showKeyboardDefault = prefs.getBool(_keyShowKeyboard) ?? true;
      _loaded = true;

      debugPrint('[AppSettings] Loaded: audio=$_audioOutputMode, keyboard=$_showKeyboardDefault');
    } catch (e) {
      debugPrint('[AppSettings] Load failed: $e');
      _loaded = true; // 使用默认值
    }
  }

  /// 设置音频输出模式
  Future<void> setAudioOutputMode(AudioOutputMode mode) async {
    _audioOutputMode = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyAudioOutput, mode.index);
      debugPrint('[AppSettings] Audio output mode → $mode');
    } catch (e) {
      debugPrint('[AppSettings] Save audio mode failed: $e');
    }
  }

  /// 设置是否默认显示键盘
  Future<void> setShowKeyboardDefault(bool value) async {
    _showKeyboardDefault = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowKeyboard, value);
      debugPrint('[AppSettings] Show keyboard default → $value');
    } catch (e) {
      debugPrint('[AppSettings] Save show keyboard failed: $e');
    }
  }
}
