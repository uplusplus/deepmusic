import 'dart:async';
import '../models/score.dart';
import '../models/note_event.dart';

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

  PracticeProgress({
    required this.currentNoteIndex,
    required this.totalNotes,
    required this.currentMeasure,
    required this.totalMeasures,
    required this.currentPage,
    required this.totalPages,
    required this.needsPageTurn,
    required this.completionPercentage,
  });
}

/// 乐谱跟随器
/// 
/// 根据用户弹奏实时定位乐谱位置
class ScoreFollower {
  final Score score;
  
  int _currentNoteIndex = 0;
  int _currentMeasure = 1;
  int _currentPage = 1;
  bool _isFinished = false;

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

  ScoreFollower(this.score);

  /// 处理 MIDI 事件
  void processMidiEvent(NoteEvent event) {
    if (_isFinished) return;

    final expectedNote = getCurrentExpectedNote();
    if (expectedNote == null) return;

    // 检查音符是否匹配
    if (event.noteNumber == expectedNote.pitchNumber) {
      // 正确！前进到下一个音符
      _currentNoteIndex++;
      
      // 检查是否需要更新小节
      _updateMeasure();
      
      // 检查是否需要翻页
      _checkPageTurn();
      
      // 检查是否完成
      _checkFinished();
      
      // 发送进度更新
      _emitProgress();
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

  /// 跳转到指定小节
  void jumpToMeasure(int measureNumber) {
    for (int i = 0; i < score.allNotes.length; i++) {
      if (score.allNotes[i].measureNumber >= measureNumber) {
        _currentNoteIndex = i;
        _currentMeasure = measureNumber;
        _emitProgress();
        break;
      }
    }
  }

  /// 重置
  void reset() {
    _currentNoteIndex = 0;
    _currentMeasure = 1;
    _currentPage = 1;
    _isFinished = false;
    _emitProgress();
  }

  void _updateMeasure() {
    if (_currentNoteIndex < score.allNotes.length) {
      _currentMeasure = score.allNotes[_currentNoteIndex].measureNumber;
    }
  }

  void _checkPageTurn() {
    // 简单逻辑：每 4 个小节换一页
    // TODO: 根据实际乐谱渲染计算
    final newPage = (_currentMeasure / 4).ceil();
    if (newPage != _currentPage) {
      _currentPage = newPage;
    }
  }

  bool get needsPageTurn {
    // 在当前页倒数第 2 小节时提示翻页
    final measureInPage = _currentMeasure % 4;
    return measureInPage == 3; // 第 4 小节前
  }

  void _checkFinished() {
    if (_currentNoteIndex >= score.allNotes.length) {
      _isFinished = true;
    }
  }

  void _emitProgress() {
    final progress = PracticeProgress(
      currentNoteIndex: _currentNoteIndex,
      totalNotes: score.allNotes.length,
      currentMeasure: _currentMeasure,
      totalMeasures: score.totalMeasures,
      currentPage: _currentPage,
      totalPages: (score.totalMeasures / 4).ceil(),
      needsPageTurn: needsPageTurn,
      completionPercentage: _currentNoteIndex / score.allNotes.length,
    );
    _progressController.add(progress);
  }

  void dispose() {
    _progressController.close();
  }
}
