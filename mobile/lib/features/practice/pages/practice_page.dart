import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class PracticePage extends StatefulWidget {
  final String scoreId;

  const PracticePage({
    super.key,
    required this.scoreId,
  });

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  bool _isPlaying = false;
  int _currentMeasure = 1;
  int _totalMeasures = 32;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('练习中'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: 练习设置
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 进度条
          LinearProgressIndicator(
            value: _currentMeasure / _totalMeasures,
            backgroundColor: AppColors.divider,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),

          // 乐谱区域
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '乐谱跟随区域',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前: 第 $_currentMeasure 小节',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    // TODO: 集成 OSMD WebView with highlight
                  ],
                ),
              ),
            ),
          ),

          // 键盘可视化
          Container(
            height: 120,
            color: Colors.grey[100],
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(14, (index) {
                  final isBlack = [1, 3, 6, 8, 10].contains(index % 12);
                  final isCurrent = index == 5; // Mock: 当前应该弹 C
                  
                  if (isBlack) {
                    return Container(
                      width: 20,
                      height: 70,
                      margin: const EdgeInsets.symmetric(horizontal: -10),
                      decoration: BoxDecoration(
                        color: isCurrent ? AppColors.primary : Colors.black,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                    );
                  }
                  
                  return Container(
                    width: 30,
                    height: 100,
                    decoration: BoxDecoration(
                      color: isCurrent ? AppColors.primaryLight : Colors.white,
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(4),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          // 控制面板
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 状态信息
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem('音准', '100%', AppColors.success),
                    _buildStatItem('节奏', '95%', AppColors.success),
                    _buildStatItem('完成度', '${((_currentMeasure / _totalMeasures) * 100).toInt()}%', AppColors.info),
                  ],
                ),
                const SizedBox(height: 16),

                // 控制按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      onPressed: () => _jumpToMeasure(1),
                      iconSize: 32,
                    ),
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                      onPressed: _togglePlay,
                      iconSize: 48,
                      color: AppColors.primary,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: () => _jumpToMeasure(_totalMeasures),
                      iconSize: 32,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _reset,
                      iconSize: 32,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      // TODO: 开始监听 MIDI 输入
    } else {
      // TODO: 暂停
    }
  }

  void _jumpToMeasure(int measure) {
    setState(() {
      _currentMeasure = measure.clamp(1, _totalMeasures);
    });
  }

  void _reset() {
    setState(() {
      _currentMeasure = 1;
      _isPlaying = false;
    });
  }
}
