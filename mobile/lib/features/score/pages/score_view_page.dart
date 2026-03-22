import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/providers/score_provider.dart';
import '../../../data/repositories/score_repository.dart';
import '../../midi/services/midi_service.dart';
import '../../settings/services/app_settings.dart';
import '../services/musicxml_parser.dart';
import '../widgets/score_renderer.dart';
import '../../practice/services/auto_player.dart';
import '../../practice/widgets/piano_keyboard.dart';

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

  // 当前乐谱 ID（支持切换）
  late String _currentScoreId;

  // XML 缓存（旋转/重建时不重复下载）
  static final Map<String, String> _xmlCache = {};

  // 渲染状态
  String? _xmlContent;
  bool _isLoadingXml = true;
  String? _xmlError;
  int _highlightMeasure = 1;

  // 自动播放
  AutoPlayer? _autoPlayer;
  StreamSubscription<AutoPlayState>? _playStateSub;
  StreamSubscription<int>? _measureSub;
  StreamSubscription<PlayingNoteEvent>? _noteSub;
  AutoPlayState _playState = AutoPlayState.initial();
  double _playbackRate = 1.0;

  // 播放中的音符（虚拟键盘高亮）
  final Set<int> _playingNotes = {};
  int _playingVersion = 0;

  // 键盘显示控制
  late bool _showKeyboard;

  // 变速选项
  static const _rateOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // MIDI 音量 (0-127)
  final MidiService _midiService = MidiService();
  double _midiVolume = 100;

  @override
  void initState() {
    super.initState();
    _currentScoreId = widget.scoreId;
    _showKeyboard = AppSettings().showKeyboardDefault;
    // 如果有缓存，不显示 loading
    final cached = _xmlCache[_currentScoreId];
    if (cached != null) {
      _xmlContent = cached;
      _isLoadingXml = false;
    }
    _loadScoreXml();
  }

  @override
  void dispose() {
    _playStateSub?.cancel();
    _measureSub?.cancel();
    _noteSub?.cancel();
    _autoPlayer?.dispose();
    super.dispose();
  }

  /// 从 XML 内容解析 Score 并初始化 AutoPlayer
  void _initAutoPlayerFromXml(String xmlContent) {
    try {
      final score = MusicXmlParser.parseString(
        xmlContent,
        scoreId: _currentScoreId,
      );

      // 释放旧的
      _playStateSub?.cancel();
      _measureSub?.cancel();
      _noteSub?.cancel();
      _autoPlayer?.dispose();

      final player = AutoPlayer(score);

      // 监听播放状态
      _playStateSub = player.stateStream.listen((state) {
        if (mounted) setState(() => _playState = state);
      });

      // 监听小节变更 → 驱动 OSMD 高亮跟随
      _measureSub = player.measureStream.listen((measure) {
        if (mounted) setState(() => _highlightMeasure = measure);
      });

      // 监听音符事件 → 驱动虚拟键盘高亮
      _noteSub = player.noteStream.listen((event) {
        if (!mounted) return;
        setState(() {
          if (event.isOn) {
            _playingNotes.add(event.noteNumber);
          } else {
            _playingNotes.remove(event.noteNumber);
          }
          _playingVersion++;
        });
      });

      _autoPlayer = player;
      debugPrint('[ScoreViewPage] AutoPlayer initialized: ${score.totalMeasures} measures, ${score.formattedDuration}');
    } catch (e) {
      debugPrint('[ScoreViewPage] AutoPlayer init failed: $e');
    }
  }

  Future<void> _loadScoreXml() async {
    // 有缓存直接用，不重新下载
    final cached = _xmlCache[_currentScoreId];
    if (cached != null) {
      debugPrint('[ScoreViewPage] Using cached XML for $_currentScoreId');
      if (mounted) {
        setState(() {
          _xmlContent = cached;
          _isLoadingXml = false;
          _xmlError = null;
        });
        _initAutoPlayerFromXml(cached);
      }
      return;
    }

    setState(() {
      _isLoadingXml = true;
      _xmlError = null;
    });

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final xml = await _scoreRepo.getScoreXml(_currentScoreId);
        _xmlCache[_currentScoreId] = xml;
        if (mounted) {
          setState(() {
            _xmlContent = xml;
            _isLoadingXml = false;
          });
          _initAutoPlayerFromXml(xml);
        }
        return;
      } catch (e) {
        debugPrint('[ScoreViewPage] loadScoreXml attempt $attempt/$maxRetries failed: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        // 最后一次也失败了
        if (mounted) {
          setState(() {
            _xmlError = e.toString();
            _isLoadingXml = false;
          });
        }
      }
    }
  }

  /// 切换到另一首乐谱
  void _switchScore(ScoreModel newScore) {
    if (newScore.id == _currentScoreId) return;

    // 停止当前播放
    _autoPlayer?.stop();

    setState(() {
      _currentScoreId = newScore.id;
      _xmlContent = null;
      _highlightMeasure = 1;
      _playState = AutoPlayState.initial();
      _isFavorite = false;
    });

    // 刷新详情 provider
    ref.invalidate(scoreDetailProvider(newScore.id));

    // 重新加载 XML
    _loadScoreXml();
  }

  Future<void> _toggleFavorite() async {
    if (_isFavoriteLoading) return;
    setState(() => _isFavoriteLoading = true);

    try {
      if (_isFavorite) {
        await _scoreRepo.unfavoriteScore(_currentScoreId);
      } else {
        await _scoreRepo.favoriteScore(_currentScoreId);
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
        const SnackBar(content: Text('乐谱加载中，请稍候...')),
      );
      return;
    }

    if (_playState.isPlaying && !_playState.isPaused) {
      _autoPlayer!.pause();
      setState(() {
        _playingNotes.clear();
        _playingVersion++;
      });
    } else {
      _autoPlayer!.play(fromMeasure: _highlightMeasure, rate: _playbackRate);
    }
  }

  void _stopPlay() {
    _autoPlayer?.stop();
    setState(() {
      _playingNotes.clear();
      _playingVersion++;
    });
  }

  void _changeRate(double rate) {
    setState(() => _playbackRate = rate);
    _autoPlayer?.setPlaybackRate(rate);
  }

  void _cycleRate() {
    final idx = _rateOptions.indexOf(_playbackRate);
    final next = _rateOptions[(idx + 1) % _rateOptions.length];
    _changeRate(next);
  }

  @override
  Widget build(BuildContext context) {
    final scoreAsync = ref.watch(scoreDetailProvider(_currentScoreId));

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
        title: Text(score.title, style: const TextStyle(fontSize: 16)),
        actions: [
          // 乐谱列表按钮
          IconButton(
            icon: const Icon(Icons.queue_music, size: 22),
            tooltip: '乐谱列表',
            onPressed: () => _showScoreListSheet(context),
          ),
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? AppColors.error : null,
              size: 22,
            ),
            onPressed: _isFavoriteLoading ? null : _toggleFavorite,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: isLandscape
          ? _buildLandscapeView(score)
          : _buildPortraitView(score),
    );
  }

  // ═══════════════════════════════════════
  // 竖屏布局
  // ═══════════════════════════════════════

  Widget _buildPortraitView(ScoreModel score) {
    return Column(
      children: [
        // 顶部紧凑信息条
        _buildCompactInfoBar(score),
        // 乐谱渲染区域（主区域）
        Expanded(child: _buildScoreRenderer()),
        // 虚拟键盘（播放时显示，固定高度避免布局异常）
        if (_playState.isPlaying && _showKeyboard)
          SizedBox(
            height: 200,
            child: PianoKeyboard(
              expectedPitches: const {},
              playingNotes: _playingNotes,
              playingVersion: _playingVersion,
              height: 200,
            ),
          ),
        // 底部播放控制栏
        _buildPlayerBar(score),
      ],
    );
  }

  // ═══════════════════════════════════════
  // 横屏布局
  // ═══════════════════════════════════════

  Widget _buildLandscapeView(ScoreModel score) {
    return Row(
      children: [
        // 左: 乐谱 + 键盘
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _buildScoreRenderer()),
              if (_playState.isPlaying && _showKeyboard)
                SizedBox(
                  height: 160,
                  child: PianoKeyboard(
                    expectedPitches: const {},
                    playingNotes: _playingNotes,
                    playingVersion: _playingVersion,
                    height: 160,
                  ),
                ),
            ],
          ),
        ),
        // 右: 控制面板
        Container(
          width: 280,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            children: [
              _buildCompactInfoBar(score),
              // 乐谱列表
              Expanded(child: _buildScoreListEmbedded()),
              _buildPlayerBar(score),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // 乐谱列表组件
  // ═══════════════════════════════════════

  /// 横屏侧栏内嵌乐谱列表
  Widget _buildScoreListEmbedded() {
    final scoresAsync = ref.watch(scoreListProvider(const ScoreListParams(limit: 100)));

    return scoresAsync.when(
      data: (result) {
        if (result.scores.isEmpty) {
          return const Center(
            child: Text('暂无乐谱', style: TextStyle(color: Colors.grey, fontSize: 13)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.queue_music, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    '乐谱列表',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${result.total}首',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: result.scores.length,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemBuilder: (context, index) {
                  final item = result.scores[index];
                  return _buildScoreListItem(item, compact: true);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (error, _) => Center(
        child: Text(
          '加载失败',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ),
    );
  }

  /// 竖屏底部抽屉
  void _showScoreListSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // 拖拽手柄
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      const Text(
                        '乐谱列表',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Consumer(
                        builder: (context, ref, _) {
                          final scoresAsync = ref.watch(
                            scoreListProvider(const ScoreListParams(limit: 100)),
                          );
                          return scoresAsync.when(
                            data: (result) => Text(
                              '${result.total}首',
                              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                            ),
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 列表
                Expanded(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final scoresAsync = ref.watch(
                        scoreListProvider(const ScoreListParams(limit: 100)),
                      );

                      return scoresAsync.when(
                        data: (result) {
                          if (result.scores.isEmpty) {
                            return const Center(
                              child: Text('暂无乐谱'),
                            );
                          }
                          return ListView.builder(
                            controller: scrollController,
                            itemCount: result.scores.length,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemBuilder: (context, index) {
                              final item = result.scores[index];
                              return _buildScoreListItem(
                                item,
                                compact: false,
                                onTap: () {
                                  _switchScore(item);
                                  Navigator.of(sheetContext).pop();
                                },
                              );
                            },
                          );
                        },
                        loading: () => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        error: (error, _) => Center(
                          child: Text('加载失败: $error'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 乐谱列表项
  Widget _buildScoreListItem(ScoreModel item, {required bool compact, VoidCallback? onTap}) {
    final isActive = item.id == _currentScoreId;

    return ListTile(
      dense: compact,
      contentPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: compact ? 28 : 36,
        height: compact ? 28 : 36,
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withOpacity(0.12)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.music_note,
          size: compact ? 16 : 20,
          color: isActive ? AppColors.primary : Colors.grey[500],
        ),
      ),
      title: Text(
        item.title,
        style: TextStyle(
          fontSize: compact ? 13 : 14,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          color: isActive ? AppColors.primary : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        item.composer,
        style: TextStyle(fontSize: compact ? 11 : 12, color: Colors.grey[500]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isActive
          ? Icon(Icons.play_circle, size: compact ? 18 : 22, color: AppColors.primary)
          : null,
      selected: isActive,
      onTap: onTap ?? () => _switchScore(item),
    );
  }

  // ═══════════════════════════════════════
  // 紧凑信息条（替代原来的 infoBar + statsBar）
  // ═══════════════════════════════════════

  Widget _buildCompactInfoBar(ScoreModel score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          // 左侧: 曲名 + 作曲家
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score.composer,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${score.keySignature} · ${score.timeSignature} · ${score.formattedDuration}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          // 右侧: 难度标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: score.difficultyColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              score.difficultyText,
              style: TextStyle(color: score.difficultyColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // 播放控制栏 — 参考 MIDI Toolbox 布局
  // ═══════════════════════════════════════

  Widget _buildPlayerBar(ScoreModel score) {
    final isPlaying = _playState.isPlaying && !_playState.isPaused;
    final hasStarted = _playState.isPlaying;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 进度条行 ──
            if (hasStarted)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        _formatTime(_playState.position),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: Colors.grey[200],
                          thumbColor: AppColors.primary,
                        ),
                        child: Slider(
                          value: _playState.progress.clamp(0.0, 1.0),
                          onChanged: (v) {
                            // TODO: seek 支持
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        _formatTime(_playState.duration),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),
                  ],
                ),
              ),

            // ── 播放按钮行 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 循环按钮
                  _buildCircleButton(
                    icon: Icons.repeat,
                    size: 20,
                    active: _playState.loopEnabled,
                    onTap: () {
                      _autoPlayer?.toggleLoop();
                    },
                  ),
                  const SizedBox(width: 8),

                  // 停止按钮
                  if (hasStarted)
                    _buildCircleButton(
                      icon: Icons.stop,
                      size: 20,
                      onTap: _stopPlay,
                    ),
                  if (hasStarted) const SizedBox(width: 8),

                  // ★ 播放/暂停按钮（居中、最大）★
                  GestureDetector(
                    onTap: _togglePlay,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isPlaying
                              ? [AppColors.primary, AppColors.primary.withOpacity(0.8)]
                              : [AppColors.primary, AppColors.primary.withOpacity(0.85)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 小节信息（播放时显示）
                  if (hasStarted)
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${_playState.currentMeasure}/${_playState.totalMeasures}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    const SizedBox(width: 52),

                  const SizedBox(width: 8),

                  // 键盘切换按钮
                  _buildCircleButton(
                    icon: _showKeyboard ? Icons.keyboard : Icons.keyboard_hide,
                    size: 20,
                    active: _showKeyboard,
                    onTap: () => setState(() => _showKeyboard = !_showKeyboard),
                  ),
                ],
              ),
            ),

            // ── 音量行 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    _midiVolume == 0 ? Icons.volume_off
                        : _midiVolume < 64 ? Icons.volume_down
                        : Icons.volume_up,
                    size: 18,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: Colors.grey[200],
                        thumbColor: AppColors.primary,
                      ),
                      child: Slider(
                        value: _midiVolume,
                        min: 0,
                        max: 127,
                        onChanged: (v) {
                          setState(() => _midiVolume = v);
                          if (_midiService.connectedDevice != null) {
                            _midiService.sendControlChange(7, v.round());
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${_midiVolume.round()}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),

            // ── 底部控制行: 变速 + BPM + 练习 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  // 变速按钮（点击循环切换）
                  GestureDetector(
                    onTap: _cycleRate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.speed, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            '${_playbackRate}x',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // BPM 显示
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.music_note, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${score.tempo} BPM',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Spacer(),
                  // 开始练习按钮
                  SizedBox(
                    height: 32,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _autoPlayer?.stop();
                        Navigator.of(context).pushNamed(
                          AppRouter.practice,
                          arguments: {'scoreId': score.id},
                        );
                      },
                      icon: const Icon(Icons.piano, size: 16),
                      label: const Text('练习', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 辅助组件 ──

  Widget _buildCircleButton({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: size,
          color: active ? AppColors.primary : Colors.grey[500],
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

  String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
