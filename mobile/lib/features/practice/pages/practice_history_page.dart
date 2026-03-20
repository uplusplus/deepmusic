import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/practice_repository.dart';

/// 练习历史页面
class PracticeHistoryPage extends StatefulWidget {
  const PracticeHistoryPage({super.key});

  @override
  State<PracticeHistoryPage> createState() => _PracticeHistoryPageState();
}

class _PracticeHistoryPageState extends State<PracticeHistoryPage> {
  final PracticeRepository _practiceRepo = PracticeRepository();

  List<PracticeRecord> _records = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _currentPage = 1;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _records = [];
    }

    try {
      final result = await _practiceRepo.getHistory(
        page: _currentPage,
        limit: _pageSize,
      );

      if (mounted) {
        setState(() {
          if (refresh) {
            _records = result.records;
          } else {
            _records.addAll(result.records);
          }
          _hasMore = _currentPage < result.totalPages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoading) return;
    _currentPage++;
    await _loadHistory();
  }

  Future<void> _deleteRecord(PracticeRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条练习记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _practiceRepo.deleteRecord(record.id);
      if (mounted) {
        setState(() {
          _records.removeWhere((r) => r.id == record.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('练习历史'),
      ),
      body: _isLoading && _records.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () => _loadHistory(refresh: true),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _records.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _records.length) {
                        _loadMore();
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return _buildRecordCard(_records[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            '还没有练习记录',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '去乐谱库选一首曲子开始练习吧',
            style: TextStyle(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(PracticeRecord record) {
    final scoreName = record.score?['title'] ?? '未知乐谱';
    final composer = record.score?['composer'] ?? '';
    final dateStr = _formatDate(record.completedAt);

    return Dismissible(
      key: Key(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _deleteRecord(record);
        return false; // 不让 Dismissible 自动删除，由 _deleteRecord 处理
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showRecordDetail(record),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 等级徽章
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _gradeColor(record.grade).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      record.grade,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _gradeColor(record.grade),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scoreName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (composer.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          composer,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildMiniStat(
                              '音准', '${record.pitchScore.toInt()}%'),
                          const SizedBox(width: 12),
                          _buildMiniStat(
                              '节奏', '${record.rhythmScore.toInt()}%'),
                          const SizedBox(width: 12),
                          Text(
                            _formatDuration(record.duration),
                            style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 分数
                Column(
                  children: [
                    Text(
                      '${record.overallScore.toInt()}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRecordDetail(PracticeRecord record) {
    final scoreName = record.score?['title'] ?? '未知乐谱';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 等级 & 分数
              Center(
                child: Column(
                  children: [
                    Text(
                      record.grade,
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        color: _gradeColor(record.grade),
                      ),
                    ),
                    Text(
                      '${record.overallScore.toInt()} 分',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scoreName,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 分数条
              _buildScoreBar('音准', record.pitchScore),
              const SizedBox(height: 12),
              _buildScoreBar('节奏', record.rhythmScore),
              const SizedBox(height: 24),

              // 统计
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildDetailStat('弹奏音符', '${record.notesPlayed}'),
                  _buildDetailStat('练习时长', _formatDuration(record.duration)),
                ],
              ),
              const SizedBox(height: 24),

              Text(
                '完成时间: ${_formatDateTime(record.completedAt)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreBar(String label, double score) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('${score.toInt()}%',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            minHeight: 8,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation(
              score >= 80
                  ? AppColors.success
                  : score >= 60
                      ? AppColors.warning
                      : AppColors.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Text(
      '$label $value',
      style: const TextStyle(color: AppColors.textHint, fontSize: 12),
    );
  }

  Widget _buildDetailStat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
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

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m分${s}秒';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}/${dt.day}';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
