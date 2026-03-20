import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/providers/score_provider.dart';
import '../../../data/repositories/score_repository.dart';

class ScoreViewPage extends ConsumerStatefulWidget {
  final String scoreId;

  const ScoreViewPage({
    super.key,
    required this.scoreId,
  });

  @override
  ConsumerState<ScoreViewPage> createState() => _ScoreViewPageState();
}

class _ScoreViewPageState extends ConsumerState<ScoreViewPage> {
  bool _isFavorite = false;
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final scoreAsync = ref.watch(scoreDetailProvider(widget.scoreId));

    return scoreAsync.when(
      data: (score) => _buildScoreView(score),
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('加载中...')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: const Text('加载失败')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(error.toString()),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(scoreDetailProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreView(ScoreModel score) {
    final totalPages = (score.measures / 4).ceil().clamp(1, 999);

    return Scaffold(
      appBar: AppBar(
        title: Text(score.title),
        actions: [
          IconButton(
            icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
            color: _isFavorite ? AppColors.error : null,
            onPressed: () {
              setState(() {
                _isFavorite = !_isFavorite;
              });
              // TODO: 调用收藏 API
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // TODO: 分享
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 乐谱信息
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        score.composer,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${score.keySignature} · ${score.timeSignature} · ${score.tempo} BPM',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (score.category != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          score.category!,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: score.difficultyColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    score.difficultyText,
                    style: TextStyle(color: score.difficultyColor),
                  ),
                ),
              ],
            ),
          ),

          // 统计信息栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.divider),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoChip(Icons.music_note, '${score.measures} 小节'),
                _buildInfoChip(Icons.timer, score.formattedDuration),
                _buildInfoChip(Icons.play_circle_outline, '${score.playCount} 次'),
                _buildInfoChip(Icons.favorite, '${score.favoriteCount}'),
              ],
            ),
          ),

          // 乐谱渲染区域 (WebView + OSMD)
          Expanded(
            child: Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.music_note, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      score.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_currentPage / $totalPages 页',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '乐谱渲染 (OSMD WebView)',
                      style: TextStyle(color: AppColors.textHint, fontSize: 12),
                    ),
                    // TODO: 集成 OSMD WebView 渲染
                  ],
                ),
              ),
            ),
          ),

          // 页面导航
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.divider),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                ),
                Text('$_currentPage / $totalPages 页'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPage < totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => _startPractice(score),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始练习'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textHint),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  void _startPractice(ScoreModel score) {
    Navigator.of(context).pushNamed(
      AppRouter.practice,
      arguments: {'scoreId': score.id},
    );
  }
}
