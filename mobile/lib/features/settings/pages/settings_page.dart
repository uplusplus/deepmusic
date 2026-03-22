import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../services/app_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = AppSettings();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── 音频设置 ──
          _buildSectionHeader('音频'),
          _buildAudioOutputTile(),
          const Divider(height: 1),

          const SizedBox(height: 8),

          // ── 乐谱播放设置 ──
          _buildSectionHeader('乐谱播放'),
          _buildShowKeyboardTile(),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildAudioOutputTile() {
    final isMidi = _settings.audioOutputMode == AudioOutputMode.midi;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isMidi ? Icons.cable : Icons.speaker,
          color: AppColors.primary,
          size: 22,
        ),
      ),
      title: const Text('音频输出'),
      subtitle: Text(
        isMidi ? 'MIDI 设备输出' : '本机播放',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: SegmentedButton<AudioOutputMode>(
        segments: const [
          ButtonSegment(
            value: AudioOutputMode.midi,
            label: Text('MIDI', style: TextStyle(fontSize: 12)),
            icon: Icon(Icons.cable, size: 16),
          ),
          ButtonSegment(
            value: AudioOutputMode.local,
            label: Text('本机', style: TextStyle(fontSize: 12)),
            icon: Icon(Icons.speaker, size: 16),
          ),
        ],
        selected: {_settings.audioOutputMode},
        onSelectionChanged: (selected) {
          if (selected.isNotEmpty) {
            setState(() {
              _settings.setAudioOutputMode(selected.first);
            });
          }
        },
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ),
    );
  }

  Widget _buildShowKeyboardTile() {
    return SwitchListTile(
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.piano,
          color: AppColors.accent,
          size: 22,
        ),
      ),
      title: const Text('默认显示键盘'),
      subtitle: const Text(
        '播放乐谱时是否默认展示虚拟钢琴键盘',
        style: TextStyle(fontSize: 12),
      ),
      value: _settings.showKeyboardDefault,
      onChanged: (value) {
        setState(() {
          _settings.setShowKeyboardDefault(value);
        });
      },
      activeColor: AppColors.primary,
    );
  }
}
