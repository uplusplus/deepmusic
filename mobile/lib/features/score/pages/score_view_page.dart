import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/providers/score_provider.dart';
import '../../../data/repositories/score_repository.dart';
import '../../midi/services/midi_service.dart';
import '../../practice/services/volume_service.dart';
import '../../settings/services/app_settings.dart';
import '../services/musicxml_parser.dart';
import '../models/score.dart' show HandMode;
import '../widgets/score_renderer.dart';
import '../../practice/services/auto_player.dart';
import '../../practice/services/audio_synth_service.dart';
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

  // 左右手模式
  HandMode _handMode = HandMode.both;

  // 分页状态
  int _currentPage = 0;
  int _totalPages = 1;
  int _totalMeasures = 0;
  static const int _measuresPerPage = 15;
  bool get _isPaged => _totalPages > 1;
  // 用 GlobalKey 访问 ScoreRenderer 的 renderPage 方法
  final GlobalKey _rendererKey = GlobalKey();

  // 切谱过渡：loading 遮罩
  bool _showLoadingOverlay = false;
  // 缓存乐谱数据，切换时保持界面不闪
  ScoreModel? _lastScore;

  // 变速选项
  static const _rateOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // 音量控制
  final MidiService _midiService = MidiService();
  final VolumeService _volumeService = VolumeService();
  final AudioSynthService _audioSynth = AudioSynthService();
  StreamSubscription<double>? _volumeSub;

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

    // 监听音量变化（外部来源，如硬件音量键）
    _volumeSub = _volumeService.volumeStream.listen((v) {
      if (mounted) setState(() {});
      // 同步到合成器增益
      if (!_volumeService.isMidiMode) {
        _audioSynth.volume = v;
      }
    });
    // 初始化合成器音量
    if (!_volumeService.isMidiMode) {
      _audioSynth.volume = _volumeService.localVolume;
    }

    // 监听硬件音量键
    _initHardwareVolumeListener();
  }

  /// 监听硬件音量键
  void _initHardwareVolumeListener() {
    // 通过 RawKeyboardListener 拦截 Android/iOS 音量键
    // Android: VolumeUp = 0xA4, VolumeDown = 0xA5
    // 实际使用 ServicesBinding 的 key event handler
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    // Android 音量键: volumeUp/volumeDown
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
      _volumeService.adjustVolume(0.05);
      return true; // 消费事件，阻止系统音量弹窗
    }
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
      _volumeService.adjustVolume(-0.05);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _volumeSub?.cancel();
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

      final player = AutoPlayer(score, handMode: _handMode);

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
    final sw = Stopwatch()..start();

    // 1. 内存缓存
    final memCached = _xmlCache[_currentScoreId];
    if (memCached != null) {
      debugPrint('[Cache] HIT memory: $_currentScoreId (${sw.elapsedMilliseconds}ms)');
      if (mounted) {
        setState(() {
          _xmlContent = memCached;
          _isLoadingXml = false;
          _xmlError = null;
        });
        _initAutoPlayerFromXml(memCached);
      }
      return;
    }

    // 2. 磁盘缓存
    try {
      final file = await _getCacheFile(_currentScoreId);
      if (await file.exists()) {
        final xml = await file.readAsString();
        _xmlCache[_currentScoreId] = xml;
        debugPrint('[Cache] HIT disk: $_currentScoreId (${sw.elapsedMilliseconds}ms, ${xml.length}chars)');
        if (mounted) {
          setState(() {
            _xmlContent = xml;
            _isLoadingXml = false;
            _xmlError = null;
          });
          _initAutoPlayerFromXml(xml);
        }
        return;
      }
    } catch (e) {
      debugPrint('[Cache] disk read error: $e');
    }

    // 3. 从服务端下载
    setState(() {
      _isLoadingXml = true;
      _xmlError = null;
    });

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final xml = await _scoreRepo.getScoreXml(_currentScoreId);
        debugPrint('[Cache] MISS → downloaded: $_currentScoreId (${sw.elapsedMilliseconds}ms, ${xml.length}chars)');

        // 写入内存缓存
        _xmlCache[_currentScoreId] = xml;

        // 写入磁盘缓存（异步，不阻塞 UI）
        _saveToDiskCache(_currentScoreId, xml);

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
        if (mounted) {
          setState(() {
            _xmlError = e.toString();
            _isLoadingXml = false;
          });
        }
      }
    }
  }

  /// 获取磁盘缓存文件路径
  Future<File> _getCacheFile(String scoreId) async {
    final dir = await getApplicationCacheDirectory();
    final cacheDir = Directory('${dir.path}/score_xml');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/$scoreId.xml');
  }

  /// 异步写入磁盘缓存
  Future<void> _saveToDiskCache(String scoreId, String xml) async {
    try {
      final file = await _getCacheFile(scoreId);
      await file.writeAsString(xml);
      debugPrint('[Cache] saved to disk: $scoreId (${xml.length}chars)');
    } catch (e) {
      debugPrint('[Cache] disk write error: $e');
    }
  }

  /// 切换到另一首乐谱
  void _switchScore(ScoreModel newScore) {
    if (newScore.id == _currentScoreId) return;
    debugPrint('[ScoreView] _switchScore: ${newScore.id}');

    // 停止当前播放
    _autoPlayer?.stop();

    setState(() {
      _currentScoreId = newScore.id;
      _showLoadingOverlay = true;  // 显示遮罩覆盖旧内容，WebView 保持存活
      _highlightMeasure = 1;
      _playState = AutoPlayState.initial();
      _isFavorite = false;
      // 重置分页
      _currentPage = 0;
      _totalPages = 1;
      _totalMeasures = 0;
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

  void _cycleHandMode() {
    setState(() {
      _handMode = switch (_handMode) {
        HandMode.both => HandMode.rightOnly,
        HandMode.rightOnly => HandMode.leftOnly,
        HandMode.leftOnly => HandMode.both,
      };
    });
    _autoPlayer?.setHandMode(_handMode);
  }

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

    // 缓存乐谱数据
    if (scoreAsync.hasValue) {
      _lastScore = scoreAsync.requireValue;
    }

    // loading/error 时用缓存的乐谱数据保持界面不闪
    if (!scoreAsync.hasValue && _lastScore != null) {
      return _buildScoreView(_lastScore!);
    }

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
          // 练习按钮
          TextButton.icon(
            onPressed: () {
              _autoPlayer?.stop();
              Navigator.of(context).pushNamed(
                AppRouter.practice,
                arguments: {'scoreId': score.id},
              );
            },
            icon: const Icon(Icons.piano, size: 18),
            label: const Text('练习', style: TextStyle(fontSize: 14)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
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
        // 分页导航栏
        if (_isPaged) _buildPaginationBar(),
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
        // 左: 乐谱 + 分页 + 键盘
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _buildScoreRenderer()),
              if (_isPaged) _buildPaginationBar(),
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

  /// 横屏侧栏内嵌乐谱列表 — GlobalKey 保证父级 setState 时不销毁 State
  Widget _buildScoreListEmbedded() {
    return _EmbeddedScoreList(
      key: const ValueKey('embedded_score_list'),
      currentScoreId: _currentScoreId,
      onScoreTap: _switchScore,
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
        return _ScoreListSheetContent(
          currentScoreId: _currentScoreId,
          onScoreTap: (score) {
            _switchScore(score);
            // 不关闭抽屉，用户可以继续滚动和切换
          },
        );
      },
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
  // 分页导航栏
  // ═══════════════════════════════════════

  Widget _buildPaginationBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(color: AppColors.divider),
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Row(
        children: [
          // 上一页
          _PaginationButton(
            icon: Icons.chevron_left,
            onTap: _currentPage > 0 ? _prevPage : null,
          ),
          const SizedBox(width: 8),
          // 页码指示
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalPages, (i) {
                final isActive = i == _currentPage;
                return GestureDetector(
                  onTap: () => _goToPage(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.primary : Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          // 页码文字
          Text(
            '${_currentPage + 1}/$_totalPages',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(width: 8),
          // 下一页
          _PaginationButton(
            icon: Icons.chevron_right,
            onTap: _currentPage < _totalPages - 1 ? _nextPage : null,
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

                  // 左右手切换按钮
                  _buildCircleButton(
                    icon: _handMode == HandMode.both ? Icons.piano
                        : _handMode == HandMode.rightOnly ? Icons.looks_one
                        : Icons.looks_two,
                    size: 20,
                    active: _handMode != HandMode.both,
                    onTap: _cycleHandMode,
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
                    _volumeService.volume == 0 ? Icons.volume_off
                        : _volumeService.volume < 0.5 ? Icons.volume_down
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
                        value: _volumeService.volume,
                        min: 0,
                        max: 1.0,
                        onChanged: (v) {
                          _volumeService.setVolume(v);
                          // 本机模式: 同步合成器增益
                          if (!_volumeService.isMidiMode) {
                            _audioSynth.volume = v;
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      _volumeService.isMidiMode
                          ? '${_volumeService.midiVolumeCc}'
                          : '${(_volumeService.localVolume * 100).round()}%',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),

            // ── 输出模式指示 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    _volumeService.isMidiMode ? Icons.piano : Icons.speaker,
                    size: 14,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _volumeService.isMidiMode
                        ? 'MIDI音量 (${_midiService.connectedDevice?.name ?? "未连接"})'
                        : '本机音量',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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

  // ── 分页导航 ──

  void _goToPage(int page) {
    if (page < 0 || page >= _totalPages) return;
    if (page == _currentPage) return;
    debugPrint('[Pagination] go to page $page ($_measuresPerPage measures/page, total=$_totalMeasures)');
    setState(() => _currentPage = page);
    // 通过 GlobalKey 调用 ScoreRenderer 的 renderPage
    final state = _rendererKey.currentState;
    if (state != null) {
      // ScoreRenderer._ScoreRendererState has public renderPage(int) method
      (state as dynamic).renderPage(page);
    } else {
      debugPrint('[Pagination] renderer state is null!');
    }
  }

  void _nextPage() => _goToPage(_currentPage + 1);
  void _prevPage() => _goToPage(_currentPage - 1);

  Widget _buildScoreRenderer() {
    // 首次加载，还没有 XML → 显示加载指示器
    if (_xmlContent == null || _xmlContent!.isEmpty) {
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

    // 有 XML → 始终显示 ScoreRenderer（WebView 保持存活）
    // 切换乐谱时叠加 loading overlay，渲染完消失
    debugPrint('[Pagination] _isPaged=$_isPaged _totalPages=$_totalPages _currentPage=$_currentPage measuresPerPage=$_measuresPerPage totalMeasures=$_totalMeasures');
    return Stack(
      children: [
        Container(
          color: Colors.white,
          child: ScoreRenderer(
            key: _rendererKey,
            musicXml: _xmlContent!,
            highlightMeasure: _highlightMeasure,
            measuresPerPage: _measuresPerPage,
            onRendered: (info) {
              debugPrint('[Pagination] onRendered: $info');
              debugPrint('[Pagination] parsed: totalMeasures=${info.totalMeasures} page=${info.page} totalPages=${info.totalPages}');
              if (mounted) {
                setState(() {
                  _isLoadingXml = false;
                  _showLoadingOverlay = false;
                  _totalMeasures = info.totalMeasures;
                  _totalPages = info.totalPages;
                  _currentPage = info.page;
                });
              }
            },
            onError: (error) {
              debugPrint('Score render error: $error');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('渲染错误: $error')),
              );
            },
          ),
        ),

        // 切换乐谱时的加载遮罩（盖住旧内容，等新内容渲染完再淡出）
        if (_showLoadingOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 12),
                    Text('加载乐谱中...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 翻页按钮（圆角方形，禁用时半透明）
class _PaginationButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _PaginationButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? AppColors.primary.withOpacity(0.3) : Colors.grey[300]!,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? AppColors.primary : Colors.grey[300],
        ),
      ),
    );
  }
}

/// 横屏侧栏乐谱列表
/// GlobalKey 键控 ListView，父级 setState 时复用同一 State，滚动位置自然保持
class _EmbeddedScoreList extends ConsumerStatefulWidget {
  final String currentScoreId;
  final void Function(ScoreModel) onScoreTap;

  const _EmbeddedScoreList({
    super.key,
    required this.currentScoreId,
    required this.onScoreTap,
  });

  @override
  ConsumerState<_EmbeddedScoreList> createState() => _EmbeddedScoreListState();
}

class _EmbeddedScoreListState extends ConsumerState<_EmbeddedScoreList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                controller: _scrollController,
                itemCount: result.scores.length,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemBuilder: (context, index) {
                  final item = result.scores[index];
                  final isActive = item.id == widget.currentScoreId;
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    leading: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primary.withOpacity(0.12)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.music_note,
                        size: 16,
                        color: isActive ? AppColors.primary : Colors.grey[500],
                      ),
                    ),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive ? AppColors.primary : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      item.composer,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isActive
                        ? Icon(Icons.play_circle, size: 18, color: AppColors.primary)
                        : null,
                    selected: isActive,
                    onTap: () => widget.onScoreTap(item),
                  );
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
}

/// 竖屏底部抽屉乐谱列表 — 独立 widget
/// 父级 setState 不会重建此 widget；点击乐谱不关闭抽屉
class _ScoreListSheetContent extends ConsumerStatefulWidget {
  final String currentScoreId;
  final void Function(ScoreModel) onScoreTap;

  const _ScoreListSheetContent({
    required this.currentScoreId,
    required this.onScoreTap,
  });

  @override
  ConsumerState<_ScoreListSheetContent> createState() => _ScoreListSheetContentState();
}

class _ScoreListSheetContentState extends ConsumerState<_ScoreListSheetContent> {
  String _activeScoreId = '';
  final _listKey = GlobalKey(debugLabel: 'sheet_score_list');

  @override
  void initState() {
    super.initState();
    _activeScoreId = widget.currentScoreId;
  }

  @override
  void didUpdateWidget(_ScoreListSheetContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentScoreId != oldWidget.currentScoreId) {
      setState(() => _activeScoreId = widget.currentScoreId);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scoresAsync = ref.watch(scoreListProvider(const ScoreListParams(limit: 100)));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, _) {
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
                  scoresAsync.when(
                    data: (result) => Text(
                      '${result.total}首',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 列表
            Expanded(
              child: scoresAsync.when(
                data: (result) {
                  if (result.scores.isEmpty) {
                    return const Center(child: Text('暂无乐谱'));
                  }
                  return ListView.builder(
                    key: _listKey,
                    itemCount: result.scores.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (context, index) {
                      final item = result.scores[index];
                      final isActive = item.id == _activeScoreId;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.primary.withOpacity(0.12)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.music_note,
                            size: 20,
                            color: isActive ? AppColors.primary : Colors.grey[500],
                          ),
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                            color: isActive ? AppColors.primary : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          item.composer,
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isActive
                            ? Icon(Icons.play_circle, size: 22, color: AppColors.primary)
                            : null,
                        selected: isActive,
                        onTap: () {
                          setState(() => _activeScoreId = item.id);
                          widget.onScoreTap(item);
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
              ),
            ),
          ],
        );
      },
    );
  }
}
