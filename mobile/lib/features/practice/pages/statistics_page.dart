import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/practice_repository.dart';

/// 学习统计页面
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage>
    with SingleTickerProviderStateMixin {
  final PracticeRepository _practiceRepo = PracticeRepository();
  late TabController _tabController;

  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String _period = 'week';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final periods = ['week', 'month', 'all'];
        _period = periods[_tabController.index];
        _loadStats();
      }
    });
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _practiceRepo.getStats();
      if (mounted) setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习统计'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '近7天'),
            Tab(text: '近30天'),
            Tab(text: '全部'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stats == null
              ? const Center(child: Text('暂无数据'))
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 总览卡片
                        _buildSummaryCard(),
                        const SizedBox(height: 20),

                        // 等级分布
                        const Text(
                          '等级分布',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildGradeDistribution(),
                        const SizedBox(height: 20),

                        // 最佳成绩
                        const Text(
                          '最佳成绩',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTopScores(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSummaryCard() {
    final summary = _stats!['summary'] as Map<String, dynamic>? ?? {};
    final totalTime = summary['totalPracticeTime'] ?? 0;
    final totalSessions = summary['totalSessions'] ?? 0;
    final totalNotes = summary['totalNotes'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            '累计练习',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            _formatTotalTime(totalTime),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem('练习次数', '$totalSessions', Colors.white70),
              Container(width: 1, height: 30, color: Colors.white24),
              _buildSummaryItem('弹奏音符', '$totalNotes', Colors.white70),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _buildGradeDistribution() {
    final gradeDist =
        _stats!['gradeDistribution'] as Map<String, dynamic>? ?? {};
    if (gradeDist.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('暂无等级数据', style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    final grades = ['S', 'A', 'B', 'C', 'D', 'F'];
    final total =
        gradeDist.values.fold<int>(0, (sum, v) => sum + (v as int));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: grades.map((grade) {
            final count = gradeDist[grade] ?? 0;
            final ratio = total > 0 ? count / total : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      grade,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _gradeColor(grade),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 12,
                        backgroundColor: Colors.grey[100],
                        valueColor:
                            AlwaysStoppedAnimation(_gradeColor(grade)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTopScores() {
    final topScores = _stats!['topScores'] as List? ?? [];
    if (topScores.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('暂无最佳成绩', style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return Column(
      children: topScores.map<Widget>((score) {
        final title = score['title'] ?? '未知';
        final composer = score['composer'] ?? '';
        final bestScore = (score['bestScore'] as num?)?.toDouble() ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Text(
                '${bestScore.toInt()}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            title: Text(title),
            subtitle: composer.isNotEmpty ? Text(composer) : null,
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          ),
        );
      }).toList(),
    );
  }

  Color _gradeColor(String grade) {
    switch (grade) {
      case 'S':
        return Colors.amber;
      case 'A':
        return AppColors.success;
      case 'B':
        return AppColors.info;
      case 'C':
        return AppColors.warning;
      case 'D':
        return Colors.orange;
      default:
        return AppColors.error;
    }
  }

  String _formatTotalTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}
