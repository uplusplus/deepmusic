import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/providers/score_provider.dart';
import '../../../data/repositories/score_repository.dart';
import '../widgets/score_renderer.dart';
import '../../practice/services/auto_player.dart';

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

  // 自动播放
  AutoPlayer? _autoPlayer;
  AutoPlayState _playState = AutoPlayState.initial();
  double _playbackRate = 1.0;

  @override
  void initState() {
    super.initState();
    _loadScoreXml();
  }

  void _initAutoPlayer() {
    // AutoPlayer 需要 Score 对象，这里仅在播放时创建
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

  // ── 自动播放控制 ──

  void _togglePlay() {
    if (_autoPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要乐谱数据才能播放')),
      );
      return;
    }

    if (_playState.isPlaying && !_playState.isPaused) {
      _autoPlayer!.pause();
    } else {
      _autoPlayer!.play(fromMeasure: _highlightMeasure, rate: _playbackRate);
    }
  }

  void _stopPlay() {
    _autoPlayer?.stop();
  }

  void _changeRate(double rate) {
    setState(() => _playbackRate = rate);
    _autoPlayer?.setPlaybackRate(rate);
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
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

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
      body: isLandscape
          ? _buildLandscapeView(score)
          : _buildPortraitView(score),
    );
  }

  Widget _buildPortraitView(ScoreModel score) {
    return Column(
      children: [
        _buildScoreInfoBar(score),
        _buildScoreStatsBar(score),
        Expanded(child: _buildScoreRenderer()),
      ],
    );
  }

  Widget _buildLandscapeView(ScoreModel score) {
    return Row(
      children: [
        // 左: 乐谱 (主要区域)
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _buildScoreRenderer()),
            ],
          ),
        ),
        // 右: 信息 + 播放控制
        Container(
          width: 260,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            children: [
              _buildScoreInfoBar(score),
              _buildScoreStatsBar(score),
              const Spacer(),
              _buildPlaybackBar(score),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _autoPlayer?.stop();
                      Navigator.of(context).pushNamed(
                        AppRouter.practice,
                        arguments: {'scoreId': score.id},
                      );
                    },
                    icon: const Icon(Icons.piano),
                    label: const Text('开始练习'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScoreInfoBar(ScoreModel score) {
    return Container(
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
    );
  }

  Widget _buildScoreStatsBar(ScoreModel score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
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
    );
  }

  Widget _buildPlaybackBar(ScoreModel score) {
    final isPlaying = _playState.isPlaying && !_playState.isPaused;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // 进度条
          if (_playState.isPlaying)
            LinearProgressIndicator(
              value: _playState.progress,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              minHeight: 3,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 播放/暂停
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause_circle : Icons.play_circle,
                  size: 36,
                  color: AppColors.primary,
                ),
                onPressed: _togglePlay,
              ),
              // 停止
              if (_playState.isPlaying)
                IconButton(
                  icon: const Icon(Icons.stop_circle, size: 28, color: Colors.grey),
                  onPressed: _stopPlay,
                ),
              const SizedBox(width: 8),

              // 当前小节
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _playState.isPlaying
                          ? '第 ${_playState.currentMeasure} / ${_playState.totalMeasures} 小节'
                          : '点击 ▶ 试听',
                      style: TextStyle(
                        fontSize: 13,
                        color: _playState.isPlaying ? AppColors.textPrimary : Colors.grey,
                      ),
                    ),
                    if (_playState.isPlaying)
                      Text(
                        '${_playState.position.inSeconds}s / ${_playState.duration.inSeconds}s',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
              ),

              // 变速控制
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<double>(
                  value: _playbackRate,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 0.5, child: Text('0.5x', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 0.75, child: Text('0.75x', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 1.0, child: Text('1.0x', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 1.25, child: Text('1.25x', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 1.5, child: Text('1.5x', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 2.0, child: Text('2.0x', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) {
                    if (v != null) _changeRate(v);
                  },
                ),
              ),
            ],
          ),
        ],
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
