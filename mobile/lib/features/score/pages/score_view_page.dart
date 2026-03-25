import 'package:flutter/material.dart';

class ScoreViewPage extends StatefulWidget {
  final String scoreId;

  const ScoreViewPage({
    super.key,
    required this.scoreId,
  });

  @override
  State<ScoreViewPage> createState() => _ScoreViewPageState();
}

class _ScoreViewPageState extends State<ScoreViewPage> {
  int _currentPage = 1;
  int _totalPages = 4;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('致爱丽丝'),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite_border),
            onPressed: () {
              // TODO: 收藏
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              // TODO: 下载
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '贝多芬',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'A Minor · 3/8 · 125 BPM',
                        style: TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    '初级',
                    style: TextStyle(color: Colors.green),
                  ),
                ),
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
                    const Icon(
                      Icons.music_note,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text('乐谱渲染区域'),
                    const SizedBox(height: 8),
                    Text(
                      '第 $_currentPage / $_totalPages 页',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    // TODO: 集成 OSMD WebView
                  ],
                ),
              ),
            ),
          ),

          // 页面导航
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                ),
                Text('$_currentPage / $_totalPages'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPage < _totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: () => _startPractice(),
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始练习'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  void _startPractice() {
    Navigator.of(context).pushNamed(
      '/practice',
      arguments: {'scoreId': widget.scoreId},
    );
  }
}
