import 'dart:async';
import 'dart:math';
import '../models/score.dart';
import '../models/note_event.dart';

/// 乐谱页面布局信息
class PageLayout {
  final int pageNumber;
  final int startMeasure;
  final int endMeasure;
  final int startNoteIndex;
  final int endNoteIndex;

  PageLayout({
    required this.pageNumber,
    required this.startMeasure,
    required this.endMeasure,
    required this.startNoteIndex,
    required this.endNoteIndex,
  });

  int get measureCount => endMeasure - startMeasure + 1;
}

/// 练习进度
class PracticeProgress {
  final int currentNoteIndex;
  final int totalNotes;
  final int currentMeasure;
  final int totalMeasures;
  final int currentPage;
  final int totalPages;
  final bool needsPageTurn;
  final double completionPercentage;
  final int correctNotes;
  final int wrongNotes;
  final double pitchAccuracy;
  final double rhythmAccuracy;

  PracticeProgress({
    required this.currentNoteIndex,
    required this.totalNotes,
    required this.currentMeasure,
    required this.totalMeasures,
    required this.currentPage,
    required this.totalPages,
    required this.needsPageTurn,
    required this.completionPercentage,
    this.correctNotes = 0,
    this.wrongNotes = 0,
    this.pitchAccuracy = 1.0,
    this.rhythmAccuracy = 1.0,
  });
}

/// 乐谱跟随器
/// 
/// 根据用户弹奏实时定位乐谱位置，支持智能翻页和容错
class ScoreFollower {
  final Score score;
  final int measuresPerPage;
  
  int _currentNoteIndex = 0;
  int _currentMeasure = 1;
  int _currentPage = 1;
  bool _isFinished = false;

  // 统计
  int _correctNotes = 0;
  int _wrongNotes = 0;
  int _missedNotes = 0;
  int _extraNotes = 0;

  // 容错机制
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 5;
  int _lookAheadWindow = 3; // 向前搜索窗口

  // 时间跟踪
  DateTime? _practiceStartTime;

  // 页面布局缓存
  late List<PageLayout> _pageLayouts;

  final _progressController = StreamController<PracticeProgress>.broadcast();

  /// 进度流
  Stream<PracticeProgress> get progressStream => _progressController.stream;

  /// 当前音符索引
  int get currentNoteIndex => _currentNoteIndex;

  /// 当前小节
  int get currentMeasure => _currentMeasure;

  /// 当前页
  int get currentPage => _currentPage;

  /// 是否完成
  bool get isFinished => _isFinished;

  /// 正确音符数
  int get correctNotes => _correctNotes;

  /// 错误音符数
  int get wrongNotes => _wrongNotes;

  /// 总页数
  int get totalPages => _pageLayouts.length;

  /// 页面布局
  List<PageLayout> get pageLayouts => _pageLayouts;

  ScoreFollower(this.score, {this.measuresPerPage = 4}) {
    _pageLayouts = _buildPageLayouts();
    _practiceStartTime = DateTime.now();
  }

  /// 构建页面布局
  List<PageLayout> _buildPageLayouts() {
    final layouts = <PageLayout>[];
    final allNotes = score.allNotes;
    
    if (allNotes.isEmpty) {
      layouts.add(PageLayout(
        pageNumber: 1,
        startMeasure: 1,
        endMeasure: score.totalMeasures,
        startNoteIndex: 0,
        endNoteIndex: 0,
      ));
      return layouts;
    }

    // 按小节分组
    final measureNotes = <int, List<int>>{}; // measureNumber -> [note indices]
    for (int i = 0; i < allNotes.length; i++) {
      final measureNum = allNotes[i].measureNumber;
      measureNotes.putIfAbsent(measureNum, () => []).add(i);
    }

    final sortedMeasures = measureNotes.keys.toList()..sort();
    int pageNum = 1;
    int measureStart = sortedMeasures.isNotEmpty ? sortedMeasures.first : 1;
    int noteStart = 0;
    int measuresInPage = 0;

    for (int i = 0; i < sortedMeasures.length; i++) {
      final measureNum = sortedMeasures[i];
      measuresInPage++;

      // 每 N 个小节分一页，或者是最后一个小节
      final isLastMeasure = i == sortedMeasures.length - 1;
      final isPageFull = measuresInPage >= measuresPerPage;

      if (isPageFull || isLastMeasure) {
        final noteEnd = measureNotes[measureNum]!.last;
        layouts.add(PageLayout(
          pageNumber: pageNum,
          startMeasure: measureStart,
          endMeasure: measureNum,
          startNoteIndex: noteStart,
          endNoteIndex: noteEnd,
        ));

        if (!isLastMeasure) {
          pageNum++;
          final nextMeasure = sortedMeasures[i + 1];
          measureStart = nextMeasure;
          noteStart = measureNotes[nextMeasure]!.first;
          measuresInPage = 0;
        }
      }
    }

    return layouts;
  }

  /// 获取指定页面的布局
  PageLayout getPageLayout(int page) {
    final index = page.clamp(1, _pageLayouts.length) - 1;
    return _pageLayouts[index];
  }

  /// 处理 MIDI 事件
  void processMidiEvent(NoteEvent event) {
    if (_isFinished || !event.isNoteOn) return;

    final expectedNote = getCurrentExpectedNote();
    if (expectedNote == null) return;

    if (event.noteNumber == expectedNote.pitchNumber) {
      // 音符正确
      _correctNotes++;
      _consecutiveErrors = 0;
      _advanceToNextNote();
    } else {
      // 尝试容错：在窗口内查找匹配的音符
      bool foundInWindow = false;
      for (int offset = 1; offset <= _lookAheadWindow; offset++) {
        final futureIndex = _currentNoteIndex + offset;
        if (futureIndex < score.allNotes.length) {
          if (score.allNotes[futureIndex].pitchNumber == event.noteNumber) {
            // 用户跳过了几个音符，标记为遗漏
            for (int skip = 0; skip < offset; skip++) {
              _missedNotes++;
            }
            _currentNoteIndex = futureIndex + 1;
            _correctNotes++;
            _consecutiveErrors = 0;
            foundInWindow = true;
            _updateMeasureAndPage();
            _checkFinished();
            _emitProgress();
            break;
          }
        }
      }

      if (!foundInWindow) {
        // 真正的错误
        _wrongNotes++;
        _consecutiveErrors++;
        
        // 连续错误太多，暂停跟踪
        if (_consecutiveErrors >= _maxConsecutiveErrors) {
          debugPrint('[ScoreFollower] Too many consecutive errors, pausing tracking');
        }
        
        _emitProgress();
      }
    }
  }

  /// 前进到下一个音符
  void _advanceToNextNote() {
    _currentNoteIndex++;
    _updateMeasureAndPage();
    _checkFinished();
    _emitProgress();
  }

  /// 更新小节和页面
  void _updateMeasureAndPage() {
    if (_currentNoteIndex >= score.allNotes.length) return;

    final currentNote = score.allNotes[_currentNoteIndex];
    _currentMeasure = currentNote.measureNumber;

    // 查找当前页面
    for (final layout in _pageLayouts) {
      if (_currentMeasure >= layout.startMeasure && 
          _currentMeasure <= layout.endMeasure) {
        _currentPage = layout.pageNumber;
        break;
      }
    }
  }

  /// 获取当前应该弹奏的音符
  Note? getCurrentExpectedNote() {
    if (_currentNoteIndex >= score.allNotes.length) return null;
    return score.allNotes[_currentNoteIndex];
  }

  /// 获取接下来的 N 个音符
  List<Note> getUpcomingNotes({int count = 5}) {
    final end = (_currentNoteIndex + count).clamp(0, score.allNotes.length);
    return score.allNotes.sublist(_currentNoteIndex, end);
  }

  /// 是否需要翻页 (当前页还剩 2 小节以内)
  bool get needsPageTurn {
    final layout = getPageLayout(_currentPage);
    final remainingMeasures = layout.endMeasure - _currentMeasure;
    return remainingMeasures <= 1 && _currentPage < _pageLayouts.length;
  }

  /// 检查是否完成
  void _checkFinished() {
    if (_currentNoteIndex >= score.allNotes.length) {
      _isFinished = true;
    }
  }

  /// 发送进度更新
  void _emitProgress() {
    final totalNotes = score.allNotes.length;
    final progress = PracticeProgress(
      currentNoteIndex: _currentNoteIndex,
      totalNotes: totalNotes,
      currentMeasure: _currentMeasure,
      totalMeasures: score.totalMeasures,
      currentPage: _currentPage,
      totalPages: _pageLayouts.length,
      needsPageTurn: needsPageTurn,
      completionPercentage: totalNotes > 0 ? _currentNoteIndex / totalNotes : 0,
      correctNotes: _correctNotes,
      wrongNotes: _wrongNotes,
      pitchAccuracy: _correctNotes + _wrongNotes > 0 
        ? _correctNotes / (_correctNotes + _wrongNotes) 
        : 1.0,
      rhythmAccuracy: 1.0, // TODO: 基于时间的节奏评估
    );
    _progressController.add(progress);
  }

  /// 跳转到指定小节
  void jumpToMeasure(int measureNumber) {
    for (int i = 0; i < score.allNotes.length; i++) {
      if (score.allNotes[i].measureNumber >= measureNumber) {
        _currentNoteIndex = i;
        _currentMeasure = measureNumber;
        _updateMeasureAndPage();
        _emitProgress();
        return;
      }
    }
  }

  /// 跳转到指定页面
  void jumpToPage(int page) {
    if (page < 1 || page > _pageLayouts.length) return;
    final layout = _pageLayouts[page - 1];
    jumpToMeasure(layout.startMeasure);
  }

  /// 重置
  void reset() {
    _currentNoteIndex = 0;
    _currentMeasure = 1;
    _currentPage = 1;
    _isFinished = false;
    _correctNotes = 0;
    _wrongNotes = 0;
    _missedNotes = 0;
    _extraNotes = 0;
    _consecutiveErrors = 0;
    _practiceStartTime = DateTime.now();
    _emitProgress();
  }

  void dispose() {
    _progressController.close();
  }
}
