import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
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
  final int missedNotes;
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
    this.missedNotes = 0,
    this.pitchAccuracy = 1.0,
    this.rhythmAccuracy = 1.0,
  });
}

/// 和弦组：同一 startMs 的音符构成一个和弦
class ChordGroup {
  final List<Note> notes;
  final int startMs;

  ChordGroup({required this.notes, required this.startMs});

  bool get isChord => notes.length > 1;

  /// 获取期望音符号集合 (去重)
  Set<int> get expectedPitchNumbers =>
      notes.map((n) => n.pitchNumber).toSet();
}

/// 乐谱跟随器
///
/// 根据用户弹奏实时定位乐谱位置，支持智能翻页、容错、和弦匹配
class ScoreFollower {
  final Score score;
  final int measuresPerPage;

  // 和弦配置
  final int chordWindowMs;       // 和弦音符收集时间窗口 (默认 300ms)
  final double chordMatchRatio;  // 和弦最低匹配率 (默认 0.5)
  final int toleranceMs;         // 单音符容错等待时间 (默认 1500ms)

  int _currentGroupIndex = 0;
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
  int _lookAheadWindow = 3;

  // 和弦收集器
  DateTime? _chordCollectionStart;
  final Set<int> _collectedChordPitches = {};

  // 时间跟踪
  DateTime? _practiceStartTime;

  // 页面布局缓存
  late List<PageLayout> _pageLayouts;

  // 和弦组序列
  late List<ChordGroup> _chordGroups;

  final _progressController = StreamController<PracticeProgress>.broadcast();

  /// 进度流
  Stream<PracticeProgress> get progressStream => _progressController.stream;

  /// 当前和弦组索引
  int get currentGroupIndex => _currentGroupIndex;

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

  ScoreFollower(
    this.score, {
    this.measuresPerPage = 4,
    this.chordWindowMs = 300,
    this.chordMatchRatio = 0.5,
    this.toleranceMs = 1500,
  }) {
    _chordGroups = _buildChordGroups(score.allNotes);
    _pageLayouts = _buildPageLayouts();
    _practiceStartTime = DateTime.now();
  }

  /// 从扁平音符列表构建和弦组序列
  ///
  /// 同一 startMs (±5ms 容差) 的音符归为一个和弦组
  static List<ChordGroup> _buildChordGroups(List<Note> allNotes) {
    if (allNotes.isEmpty) return [];

    final groups = <ChordGroup>[];
    final sorted = List<Note>.from(allNotes)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    int groupStart = sorted.first.startMs;
    List<Note> currentNotes = [sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      final note = sorted[i];
      if ((note.startMs - groupStart).abs() <= 5) {
        // 同一和弦组
        currentNotes.add(note);
      } else {
        // 提交当前组，开始新组
        groups.add(ChordGroup(notes: currentNotes, startMs: groupStart));
        groupStart = note.startMs;
        currentNotes = [note];
      }
    }
    // 提交最后一组
    groups.add(ChordGroup(notes: currentNotes, startMs: groupStart));

    return groups;
  }

  /// 构建页面布局 (基于和弦组)
  List<PageLayout> _buildPageLayouts() {
    final layouts = <PageLayout>[];

    if (_chordGroups.isEmpty) {
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
    final measureGroups = <int, List<int>>{}; // measureNumber -> [group indices]
    for (int i = 0; i < _chordGroups.length; i++) {
      final measureNum = _chordGroups[i].notes.first.measureNumber;
      measureGroups.putIfAbsent(measureNum, () => []).add(i);
    }

    final sortedMeasures = measureGroups.keys.toList()..sort();
    int pageNum = 1;
    int measureStart = sortedMeasures.first;
    int groupStart = measureGroups[measureStart]!.first;
    int measuresInPage = 0;

    for (int i = 0; i < sortedMeasures.length; i++) {
      final measureNum = sortedMeasures[i];
      measuresInPage++;

      final isLastMeasure = i == sortedMeasures.length - 1;
      final isPageFull = measuresInPage >= measuresPerPage;

      if (isPageFull || isLastMeasure) {
        final lastGroupIdx = measureGroups[measureNum]!.last;
        layouts.add(PageLayout(
          pageNumber: pageNum,
          startMeasure: measureStart,
          endMeasure: measureNum,
          startNoteIndex: groupStart,
          endNoteIndex: lastGroupIdx,
        ));

        if (!isLastMeasure) {
          pageNum++;
          final nextMeasure = sortedMeasures[i + 1];
          measureStart = nextMeasure;
          groupStart = measureGroups[nextMeasure]!.first;
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

    final currentGroup = getCurrentExpectedGroup();
    if (currentGroup == null) return;

    if (currentGroup.isChord) {
      _handleChordNote(event, currentGroup);
    } else {
      _handleSingleNote(event, currentGroup);
    }
  }

  /// 处理单音符匹配
  void _handleSingleNote(NoteEvent event, ChordGroup group) {
    final expectedPitch = group.notes.first.pitchNumber;

    if (event.noteNumber == expectedPitch) {
      _correctNotes++;
      _consecutiveErrors = 0;
      _advanceToNextGroup();
    } else {
      // 容错：向前搜索
      bool foundInWindow = false;
      for (int offset = 1; offset <= _lookAheadWindow; offset++) {
        final futureIdx = _currentGroupIndex + offset;
        if (futureIdx < _chordGroups.length) {
          final futureGroup = _chordGroups[futureIdx];
          if (futureGroup.expectedPitchNumbers.contains(event.noteNumber)) {
            // 跳过了中间的音符/和弦
            for (int skip = 0; skip < offset; skip++) {
              final skipped = _chordGroups[_currentGroupIndex + skip];
              _missedNotes += skipped.notes.length;
            }
            _currentGroupIndex = futureIdx;
            _correctNotes++;
            _consecutiveErrors = 0;
            _advanceToNextGroup();
            foundInWindow = true;
            break;
          }
        }
      }

      if (!foundInWindow) {
        _wrongNotes++;
        _extraNotes++;
        _consecutiveErrors++;
        if (_consecutiveErrors >= _maxConsecutiveErrors) {
          debugPrint('[ScoreFollower] Too many consecutive errors');
        }
        _emitProgress();
      }
    }
  }

  /// 处理和弦音符匹配
  ///
  /// 收集 chordWindowMs 时间窗口内的所有音符，然后与和弦组对比
  void _handleChordNote(NoteEvent event, ChordGroup group) {
    final now = event.timestamp;

    // 开始收集
    if (_chordCollectionStart == null) {
      _chordCollectionStart = now;
      _collectedChordPitches.clear();
    }

    _collectedChordPitches.add(event.noteNumber);

    // 检查是否收集完毕（时间窗口到期 或 已收集足够音符）
    final elapsed = now.difference(_chordCollectionStart!).inMilliseconds;
    final collectedEnough = _collectedChordPitches.length >= group.expectedPitchNumbers.length;

    if (elapsed >= chordWindowMs || collectedEnough) {
      _evaluateChord(group);
    }
  }

  /// 评估收集到的和弦音符
  void _evaluateChord(ChordGroup group) {
    final expected = group.expectedPitchNumbers;
    final collected = Set<int>.from(_collectedChordPitches);

    // 匹配的音符
    final matched = collected.intersection(expected);
    final missed = expected.difference(collected);
    final extra = collected.difference(expected);

    final matchRatio = expected.isNotEmpty ? matched.length / expected.length : 0.0;

    if (matchRatio >= chordMatchRatio) {
      // 和弦匹配通过
      _correctNotes += matched.length;
      _missedNotes += missed.length;
      _consecutiveErrors = 0;
      _advanceToNextGroup();
    } else {
      // 和弦匹配失败
      _wrongNotes += group.notes.length;
      _extraNotes += extra.length;
      _consecutiveErrors++;

      // 容错：向前搜索
      bool foundAhead = false;
      for (int offset = 1; offset <= _lookAheadWindow; offset++) {
        final futureIdx = _currentGroupIndex + offset;
        if (futureIdx < _chordGroups.length) {
          final futureGroup = _chordGroups[futureIdx];
          final futureExpected = futureGroup.expectedPitchNumbers;
          final futureMatch = collected.intersection(futureExpected);
          final futureRatio =
              futureExpected.isNotEmpty ? futureMatch.length / futureExpected.length : 0.0;

          if (futureRatio >= chordMatchRatio) {
            // 用户跳过了几个和弦
            for (int skip = 0; skip < offset; skip++) {
              final skipped = _chordGroups[_currentGroupIndex + skip];
              _missedNotes += skipped.notes.length;
            }
            _currentGroupIndex = futureIdx;
            _correctNotes += futureMatch.length;
            _missedNotes += futureExpected.difference(futureMatch).length;
            _consecutiveErrors = 0;
            _advanceToNextGroup();
            foundAhead = true;
            break;
          }
        }
      }

      if (!foundAhead) {
        _emitProgress();
      }
    }

    // 重置收集器
    _chordCollectionStart = null;
    _collectedChordPitches.clear();
  }

  /// 前进到下一个和弦组
  void _advanceToNextGroup() {
    _currentGroupIndex++;
    _updateMeasureAndPage();
    _checkFinished();
    _emitProgress();
  }

  /// 更新小节和页面
  void _updateMeasureAndPage() {
    if (_currentGroupIndex >= _chordGroups.length) return;

    final currentGroup = _chordGroups[_currentGroupIndex];
    _currentMeasure = currentGroup.notes.first.measureNumber;

    for (final layout in _pageLayouts) {
      if (_currentMeasure >= layout.startMeasure &&
          _currentMeasure <= layout.endMeasure) {
        _currentPage = layout.pageNumber;
        break;
      }
    }
  }

  /// 获取当前期望的和弦组
  ChordGroup? getCurrentExpectedGroup() {
    if (_currentGroupIndex >= _chordGroups.length) return null;
    return _chordGroups[_currentGroupIndex];
  }

  /// 获取当前应该弹奏的音符 (单音符模式兼容)
  Note? getCurrentExpectedNote() {
    final group = getCurrentExpectedGroup();
    return group?.notes.first;
  }

  /// 获取接下来的 N 个音符 (跨和弦组展平)
  List<Note> getUpcomingNotes({int count = 5}) {
    final notes = <Note>[];
    for (int i = _currentGroupIndex;
        i < _chordGroups.length && notes.length < count;
        i++) {
      notes.addAll(_chordGroups[i].notes);
    }
    // 截断到 count
    return notes.take(count).toList();
  }

  /// 是否需要翻页
  bool get needsPageTurn {
    final layout = getPageLayout(_currentPage);
    final remainingMeasures = layout.endMeasure - _currentMeasure;
    return remainingMeasures <= 1 && _currentPage < _pageLayouts.length;
  }

  /// 检查是否完成
  void _checkFinished() {
    if (_currentGroupIndex >= _chordGroups.length) {
      _isFinished = true;
    }
  }

  /// 发送进度更新
  void _emitProgress() {
    final totalNotes = score.allNotes.length;
    final processedNotes = _correctNotes + _wrongNotes + _missedNotes;
    final progress = PracticeProgress(
      currentNoteIndex: _currentGroupIndex,
      totalNotes: totalNotes,
      currentMeasure: _currentMeasure,
      totalMeasures: score.totalMeasures,
      currentPage: _currentPage,
      totalPages: _pageLayouts.length,
      needsPageTurn: needsPageTurn,
      completionPercentage:
          _chordGroups.isNotEmpty ? _currentGroupIndex / _chordGroups.length : 0,
      correctNotes: _correctNotes,
      wrongNotes: _wrongNotes,
      missedNotes: _missedNotes,
      pitchAccuracy: processedNotes > 0 ? _correctNotes / processedNotes : 1.0,
      rhythmAccuracy: 1.0,
    );
    _progressController.add(progress);
  }

  /// 跳转到指定小节
  void jumpToMeasure(int measureNumber) {
    for (int i = 0; i < _chordGroups.length; i++) {
      if (_chordGroups[i].notes.first.measureNumber >= measureNumber) {
        _currentGroupIndex = i;
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
    _currentGroupIndex = 0;
    _currentMeasure = 1;
    _currentPage = 1;
    _isFinished = false;
    _correctNotes = 0;
    _wrongNotes = 0;
    _missedNotes = 0;
    _extraNotes = 0;
    _consecutiveErrors = 0;
    _chordCollectionStart = null;
    _collectedChordPitches.clear();
    _practiceStartTime = DateTime.now();
    _emitProgress();
  }

  void dispose() {
    _progressController.close();
  }
}
