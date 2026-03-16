import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: SingleChildScrollView(
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
                      child: const Icon(Icons.person, color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '音乐爱好者',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '已练习 0 小时',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
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
                  child: _buildStatCard('练习天数', '0', Icons.calendar_today),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard('完成曲目', '0', Icons.music_note),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard('平均分数', '-', Icons.star),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 菜单项
            _buildMenuItem(Icons.favorite, '我的收藏', () {}),
            _buildMenuItem(Icons.history, '练习记录', () {}),
            _buildMenuItem(Icons.download, '已下载曲谱', () {}),
            _buildMenuItem(Icons.settings, '设置', () {}),
            _buildMenuItem(Icons.help, '帮助与反馈', () {}),
            _buildMenuItem(Icons.info, '关于', () {}),
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
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
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
