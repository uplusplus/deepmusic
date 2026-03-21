import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../midi/services/midi_service.dart';
import '../../midi/providers/midi_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/constants/app_colors.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionInfo = ref.watch(midiConnectionInfoProvider);
    final MidiConnectionState connectionState = connectionInfo.state;
    final String? deviceName = connectionInfo.deviceName;
    final bool isConnected = connectionInfo.isConnected;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.piano,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DeepMusic',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Your Music AI Assistant',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // 设备连接卡片
              _buildDeviceCard(context, connectionState, deviceName),

              // MIDI 测试面板（仅连接时显示）
              if (isConnected) ...[
                const SizedBox(height: 16),
                _MidiTestPanel(),
              ],

              const SizedBox(height: 24),

              // 快速开始
              const Text(
                '快速开始',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildQuickStartGrid(context),

              const SizedBox(height: 24),

              // 最近练习
              const Text(
                '最近练习',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildRecentPractice(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildDeviceCard(
    BuildContext context,
    MidiConnectionState state,
    String? deviceName,
  ) {
    bool isConnected = state == MidiConnectionState.connected;
    bool isConnecting = state == MidiConnectionState.connecting;

    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(AppRouter.devices),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isConnected
                ? [AppColors.success, AppColors.success.withOpacity(0.8)]
                : [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isConnecting
                    ? Icons.bluetooth_searching
                    : (isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConnected
                        ? (deviceName ?? 'MIDI 设备')
                        : (isConnecting ? '正在连接...' : '连接电钢琴'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isConnected
                        ? '点击管理连接'
                        : (isConnecting ? '请稍候' : '点击连接 MIDI 设备'),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withOpacity(0.8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStartGrid(BuildContext context) {
    final items = [
      _QuickStartItem(
        icon: Icons.library_music,
        title: '乐谱库',
        subtitle: '浏览曲谱',
        color: AppColors.secondary,
        onTap: () => Navigator.of(context).pushNamed(AppRouter.scoreLibrary),
      ),
      _QuickStartItem(
        icon: Icons.piano,
        title: '自由练习',
        subtitle: '开始弹奏',
        color: AppColors.accent,
        onTap: () => Navigator.of(context).pushNamed(AppRouter.scoreLibrary),
      ),
      _QuickStartItem(
        icon: Icons.history,
        title: '练习记录',
        subtitle: '查看历史',
        color: AppColors.info,
        onTap: () => Navigator.of(context).pushNamed(AppRouter.practiceHistory),
      ),
      _QuickStartItem(
        icon: Icons.trending_up,
        title: '学习统计',
        subtitle: '查看进度',
        color: AppColors.warning,
        onTap: () => Navigator.of(context).pushNamed(AppRouter.statistics),
      ),
    ];

    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isLandscape ? 4 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: isLandscape ? 1.8 : 1.5,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildQuickStartItem(items[index]),
    );
  }

  Widget _buildQuickStartItem(_QuickStartItem item) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: item.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item.color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: item.color, size: 28),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            Text(
              item.subtitle,
              style: TextStyle(
                color: item.color,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPractice() {
    // TODO: 从本地存储加载最近练习
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.music_note_outlined,
              size: 48,
              color: AppColors.textHint,
            ),
            SizedBox(height: 16),
            Text(
              '还没有练习记录',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            Text(
              '开始你的第一次练习吧！',
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 0,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: '首页',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.library_music_outlined),
          activeIcon: Icon(Icons.library_music),
          label: '乐谱库',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: '我的',
        ),
      ],
      onTap: (index) {
        switch (index) {
          case 1:
            Navigator.of(context).pushNamed(AppRouter.scoreLibrary);
            break;
          case 2:
            Navigator.of(context).pushNamed(AppRouter.profile);
            break;
        }
      },
    );
  }
}

class _QuickStartItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  _QuickStartItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

/// MIDI 测试面板 — 连接成功后弹琴可实时看到音符
class _MidiTestPanel extends StatefulWidget {
  @override
  State<_MidiTestPanel> createState() => _MidiTestPanelState();
}

class _MidiTestPanelState extends State<_MidiTestPanel> {
  final MidiService _midiService = MidiService();
  StreamSubscription? _midiSub;
  final List<String> _recentNotes = [];
  int _noteCount = 0;

  @override
  void initState() {
    super.initState();
    _midiSub = _midiService.midiStream.listen((event) {
      if (event.type == MidiEventType.noteOn && event.velocity > 0) {
        setState(() {
          _noteCount++;
          _recentNotes.add(event.noteName);
          if (_recentNotes.length > 12) _recentNotes.removeAt(0);
        });
      }
    });
  }

  @override
  void dispose() {
    _midiSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              const Text(
                'MIDI 测试',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const Spacer(),
              Text(
                '已接收 $_noteCount 个音符',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_recentNotes.isEmpty)
            const Text(
              '🎹 在钢琴上弹几个音试试',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _recentNotes.map((note) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  note,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.success,
                  ),
                ),
              )).toList(),
            ),
        ],
      ),
    );
  }
}
