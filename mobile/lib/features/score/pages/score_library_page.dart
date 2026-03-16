import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class ScoreLibraryPage extends StatefulWidget {
  const ScoreLibraryPage({super.key});

  @override
  State<ScoreLibraryPage> createState() => _ScoreLibraryPageState();
}

class _ScoreLibraryPageState extends State<ScoreLibraryPage> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  // TODO: 从数据源加载曲谱
  final List<Map<String, dynamic>> _mockScores = [
    {
      'id': '1',
      'title': '致爱丽丝',
      'composer': '贝多芬',
      'difficulty': 'beginner',
      'duration': '3:00',
    },
    {
      'id': '2',
      'title': '小步舞曲',
      'composer': '巴赫',
      'difficulty': 'beginner',
      'duration': '2:00',
    },
    {
      'id': '3',
      'title': '梦幻曲',
      'composer': '舒曼',
      'difficulty': 'intermediate',
      'duration': '3:30',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '古典'),
            Tab(text: '流行'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildScoreList(),
          _buildScoreList(filter: '古典'),
          _buildScoreList(filter: '流行'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: 实现上传乐谱
        },
        icon: const Icon(Icons.upload),
        label: const Text('上传乐谱'),
      ),
    );
  }

  Widget _buildScoreList({String? filter}) {
    final scores = _mockScores.where((score) {
      if (filter != null) {
        // TODO: 实现实际的分类筛选
        return true;
      }
      if (_searchQuery.isNotEmpty) {
        return score['title'].toString().toLowerCase().contains(
          _searchQuery.toLowerCase(),
        );
      }
      return true;
    }).toList();

    if (scores.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note_outlined, size: 64, color: AppColors.textHint),
            SizedBox(height: 16),
            Text(
              '暂无曲谱',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: scores.length,
      itemBuilder: (context, index) => _buildScoreCard(scores[index]),
    );
  }

  Widget _buildScoreCard(Map<String, dynamic> score) {
    Color difficultyColor;
    String difficultyText;
    
    switch (score['difficulty']) {
      case 'beginner':
        difficultyColor = AppColors.success;
        difficultyText = '初级';
        break;
      case 'intermediate':
        difficultyColor = AppColors.warning;
        difficultyText = '中级';
        break;
      case 'advanced':
        difficultyColor = AppColors.error;
        difficultyText = '高级';
        break;
      default:
        difficultyColor = AppColors.textSecondary;
        difficultyText = '未知';
    }

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
                      score['title'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      score['composer'],
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: difficultyColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            difficultyText,
                            style: TextStyle(
                              color: difficultyColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          score['duration'],
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
              // 操作按钮
              IconButton(
                icon: const Icon(Icons.play_circle_outline),
                color: AppColors.primary,
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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

  void _openScore(Map<String, dynamic> score) {
    Navigator.of(context).pushNamed(
      AppRouter.scoreView,
      arguments: {'id': score['id']},
    );
  }

  void _startPractice(Map<String, dynamic> score) {
    Navigator.of(context).pushNamed(
      AppRouter.practice,
      arguments: {'scoreId': score['id']},
    );
  }
}
