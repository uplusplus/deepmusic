import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/repositories/auth_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthRepository _authRepo = AuthRepository();
  UserInfo? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final user = await _authRepo.getCurrentUser();
      if (mounted) setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _authRepo.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(AppRouter.auth, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 用户信息卡片
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: AppColors.primary,
                            child: Text(
                              (_user?.nickname ?? '?')[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _user?.nickname ?? '未登录',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _user != null
                                      ? '已练习 ${_user!.formattedPracticeTime}'
                                      : '登录后同步数据',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          if (_user != null)
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                // TODO: 编辑资料
                              },
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 统计数据
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          '练习次数',
                          '${_user?.totalSessions ?? 0}',
                          Icons.calendar_today,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          '弹奏音符',
                          '${_user?.totalNotes ?? 0}',
                          Icons.music_note,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          '练习时长',
                          _user?.formattedPracticeTime ?? '0m',
                          Icons.timer,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 菜单项
                  _buildMenuItem(Icons.favorite, '我的收藏', () {
                    // TODO: 收藏列表
                  }),
                  _buildMenuItem(Icons.history, '练习记录', () {
                    Navigator.of(context).pushNamed(AppRouter.practiceHistory);
                  }),
                  _buildMenuItem(Icons.trending_up, '学习统计', () {
                    Navigator.of(context).pushNamed(AppRouter.statistics);
                  }),
                  _buildMenuItem(Icons.bluetooth, 'MIDI 设备', () {
                    Navigator.of(context).pushNamed(AppRouter.devices);
                  }),

                  const Divider(height: 32),

                  _buildMenuItem(Icons.settings, '设置', () {
            Navigator.of(context).pushNamed(AppRouter.settingsPage);
          }),
                  _buildMenuItem(Icons.help, '帮助与反馈', () {}),
                  _buildMenuItem(Icons.info, '关于 DeepMusic', () {}),

                  const SizedBox(height: 16),

                  // 登出 / 登录按钮
                  if (_user != null)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('退出登录'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context)
                              .pushNamedAndRemoveUntil(AppRouter.auth, (_) => false);
                        },
                        icon: const Icon(Icons.login),
                        label: const Text('登录 / 注册'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
      onTap: onTap,
    );
  }
}
