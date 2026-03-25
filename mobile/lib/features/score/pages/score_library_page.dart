import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/providers/score_provider.dart';
import '../../../data/repositories/score_repository.dart';

class ScoreLibraryPage extends ConsumerStatefulWidget {
  const ScoreLibraryPage({super.key});

  @override
  ConsumerState<ScoreLibraryPage> createState() => _ScoreLibraryPageState();
}

class _ScoreLibraryPageState extends ConsumerState<ScoreLibraryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  final List<String> _categories = ['全部', '古典', '流行', '影视', '民歌', '爵士'];
  String _selectedCategory = '全部';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedCategory = _categories[_tabController.index];
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('乐谱库'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _categories.map((c) => Tab(text: c)).toList(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
        ],
      ),
      body: _searchQuery.isNotEmpty
          ? _buildSearchResults()
          : _buildCategoryList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).pushNamed(AppRouter.scoreUpload);
        },
        icon: const Icon(Icons.upload),
        label: const Text('上传乐谱'),
      ),
    );
  }

  Widget _buildCategoryList() {
    final category = _selectedCategory == '全部' ? null : _selectedCategory;
    final scoresAsync = ref.watch(
      scoreListProvider(ScoreListParams(category: category, limit: 50)),
    );

    return scoresAsync.when(
      data: (result) {
        if (result.scores.isEmpty) {
          return _buildEmptyState('暂无${_selectedCategory}曲谱');
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(scoreListProvider);
          },
          child: _buildScoreList(result.scores),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildSearchResults() {
    final scoresAsync = ref.watch(scoreSearchProvider(_searchQuery));

    return scoresAsync.when(
      data: (scores) {
        if (scores.isEmpty) {
          return _buildEmptyState('未找到 "$_searchQuery" 相关曲谱');
        }
        return _buildScoreList(scores);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildScoreList(List<ScoreModel> scores) {
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    if (isLandscape) {
      // 横屏: 两列网格
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 3.5,
        ),
        itemCount: scores.length,
        itemBuilder: (context, index) => _buildScoreCard(scores[index]),
      );
    }

    // 竖屏: 列表
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: scores.length,
      itemBuilder: (context, index) => _buildScoreCard(scores[index]),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.music_note_outlined, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          Text('加载失败', style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 8),
          Text(error, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.invalidate(scoreListProvider),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCard(ScoreModel score) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openScore(score),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 封面占位
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.music_note,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      score.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      score.composer,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: score.difficultyColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            score.difficultyText,
                            style: TextStyle(
                              color: score.difficultyColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          score.formattedDuration,
                          style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        if (score.playCount > 0)
                          Text(
                            '♪ ${score.playCount}',
                            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // 播放按钮
              IconButton(
                icon: const Icon(Icons.play_circle_outline),
                color: AppColors.primary,
                iconSize: 36,
                onPressed: () => _startPractice(score),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('搜索曲谱'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入曲名或作曲家',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          onSubmitted: (value) {
            Navigator.pop(context);
            setState(() {
              _searchQuery = value;
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _searchQuery = '';
              });
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }

  void _openScore(ScoreModel score) {
    Navigator.of(context).pushNamed(
      AppRouter.scoreView,
      arguments: {'id': score.id},
    );
  }

  void _startPractice(ScoreModel score) {
    Navigator.of(context).pushNamed(
      AppRouter.practice,
      arguments: {'scoreId': score.id},
    );
  }
}
