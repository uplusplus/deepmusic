import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/providers/score_provider.dart';
import '../../../data/repositories/score_repository.dart';
import '../widgets/score_renderer.dart';

class ScoreViewPage extends ConsumerStatefulWidget {
  final String scoreId;

  const ScoreViewPage({super.key, required this.scoreId});

  @override
  ConsumerState<ScoreViewPage> createState() => _ScoreViewPageState();
}

class _ScoreViewPageState extends ConsumerState<ScoreViewPage> {
  final ScoreRepository _scoreRepo = ScoreRepository();
  bool _isFavorite = false;
  bool _isFavoriteLoading = false;

  // 渲染状态
  String? _xmlContent;
  bool _isLoadingXml = true;
  String? _xmlError;
  int _highlightMeasure = 1;

  @override
  void initState() {
    super.initState();
    _loadScoreXml();
  }

  Future<void> _loadScoreXml() async {
    setState(() {
      _isLoadingXml = true;
      _xmlError = null;
    });

    try {
      final xml = await _scoreRepo.getScoreXml(widget.scoreId);
      if (mounted) {
        setState(() {
          _xmlContent = xml;
          _isLoadingXml = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _xmlError = e.toString();
          _isLoadingXml = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (_isFavoriteLoading) return;
    setState(() => _isFavoriteLoading = true);

    try {
      if (_isFavorite) {
        await _scoreRepo.unfavoriteScore(widget.scoreId);
      } else {
        await _scoreRepo.favoriteScore(widget.scoreId);
      }
      if (mounted) setState(() => _isFavorite = !_isFavorite);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isFavoriteLoading = false);
    }
  }

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
    return Scaffold(
      appBar: AppBar(
        title: Text(score.title),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? AppColors.error : null,
            ),
            onPressed: _isFavoriteLoading ? null : _toggleFavorite,
          ),
        ],
      ),
      body: Column(
        children: [
          // 乐谱信息栏
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
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

          // 统计信息
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoChip(Icons.music_note, '${score.measures} 小节'),
                _buildInfoChip(Icons.timer, score.formattedDuration),
                _buildInfoChip(
                    Icons.play_circle_outline, '${score.playCount} 次'),
                _buildInfoChip(Icons.favorite, '${score.favoriteCount}'),
              ],
            ),
          ),

          // ★ 乐谱渲染区 (OSMD WebView)
          Expanded(
            child: _buildScoreRenderer(),
          ),
        ],
      ),

      // 底部: 开始练习
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pushNamed(
              AppRouter.practice,
              arguments: {'scoreId': score.id},
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始练习'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreRenderer() {
    if (_isLoadingXml) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 12),
            Text('加载乐谱文件...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_xmlError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_xmlError!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadScoreXml,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_xmlContent == null || _xmlContent!.isEmpty) {
      return const Center(
        child: Text('乐谱文件为空', style: TextStyle(color: Colors.grey)),
      );
    }

    return ScoreRenderer(
      musicXml: _xmlContent!,
      highlightMeasure: _highlightMeasure,
      onRendered: (info) {
        debugPrint('Score rendered: $info');
      },
      onError: (error) {
        debugPrint('Score render error: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('渲染错误: $error')),
        );
      },
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textHint),
        const SizedBox(width: 4),
        Text(text,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}
