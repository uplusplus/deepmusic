import '../../score/models/score.dart';
import 'note_event.dart';

/// 音符评估结果
class NoteEvaluation {
  final Note expected;
  final NoteEvent played;
  
  /// 音准是否正确
  final bool isPitchCorrect;
  
  /// 节奏准确度 (0.0 - 1.0)
  final double timingAccuracy;
  
  /// 时值偏差 (毫秒)
  final int timingDeviationMs;
  
  /// 是否遗漏
  final bool isMissed;
  
  /// 是否多余
  final bool isExtra;

  NoteEvaluation({
    required this.expected,
    required this.played,
    required this.isPitchCorrect,
    required this.timingAccuracy,
    required this.timingDeviationMs,
    this.isMissed = false,
    this.isExtra = false,
  });

  /// 总体是否正确
  bool get isCorrect => isPitchCorrect && timingAccuracy > 0.8;
}

/// 练习报告
class PracticeReport {
  final String scoreId;
  final DateTime startTime;
  final DateTime endTime;
  
  final int totalNotes;
  final int correctNotes;
  final int wrongNotes;
  final int missedNotes;
  final int extraNotes;
  
  final double pitchScore;      // 0-100
  final double rhythmScore;     // 0-100
  final double overallScore;    // 0-100
  
  final Duration duration;
  final List<NoteEvaluation> evaluations;

  PracticeReport({
    required this.scoreId,
    required this.startTime,
    required this.endTime,
    required this.totalNotes,
    required this.correctNotes,
    required this.wrongNotes,
    required this.missedNotes,
    required this.extraNotes,
    required this.pitchScore,
    required this.rhythmScore,
    required this.overallScore,
    required this.duration,
    required this.evaluations,
  });

  /// 正确率
  double get accuracyRate => 
    totalNotes > 0 ? correctNotes / totalNotes : 0;

  /// 格式化时长
  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}分${seconds}秒';
  }

  /// 等级
  String get grade {
    if (overallScore >= 95) return 'S';
    if (overallScore >= 90) return 'A';
    if (overallScore >= 80) return 'B';
    if (overallScore >= 70) return 'C';
    if (overallScore >= 60) return 'D';
    return 'F';
  }
}

/// 音符评估器
/// 
/// 简化版：基于规则的音符评估
class NoteEvaluator {
  /// 允许的时间偏差 (毫秒)
  final int timingToleranceMs;

  NoteEvaluator({
    this.timingToleranceMs = 200,
  });

  /// 评估单个音符
  NoteEvaluation evaluate({
    required Note expected,
    required NoteEvent played,
    required int expectedStartTimeMs,
    required int playedStartTimeMs,
  }) {
    // 检查音准
    final isPitchCorrect = played.noteNumber == expected.pitchNumber;

    // 检查节奏
    final timingDeviation = (playedStartTimeMs - expectedStartTimeMs).abs();
    final timingAccuracy = _calculateTimingAccuracy(timingDeviation);

    return NoteEvaluation(
      expected: expected,
      played: played,
      isPitchCorrect: isPitchCorrect,
      timingAccuracy: timingAccuracy,
      timingDeviationMs: timingDeviation,
    );
  }

  /// 生成练习报告
  PracticeReport generateReport({
    required String scoreId,
    required DateTime startTime,
    required DateTime endTime,
    required List<NoteEvaluation> evaluations,
  }) {
    int correct = 0;
    int wrong = 0;
    int missed = 0;
    int extra = 0;

    for (final eval in evaluations) {
      if (eval.isMissed) {
        missed++;
      } else if (eval.isExtra) {
        extra++;
      } else if (eval.isCorrect) {
        correct++;
      } else {
        wrong++;
      }
    }

    final totalNotes = evaluations.where((e) => !e.isExtra).length;
    
    // 计算分数
    final pitchScore = totalNotes > 0 
      ? (correct / totalNotes) * 100 
      : 0;
    
    final avgTimingAccuracy = evaluations.isNotEmpty
      ? evaluations.map((e) => e.timingAccuracy).reduce((a, b) => a + b) / evaluations.length
      : 0;
    final rhythmScore = avgTimingAccuracy * 100;
    
    final overallScore = (pitchScore * 0.6 + rhythmScore * 0.4);

    return PracticeReport(
      scoreId: scoreId,
      startTime: startTime,
      endTime: endTime,
      totalNotes: totalNotes,
      correctNotes: correct,
      wrongNotes: wrong,
      missedNotes: missed,
      extraNotes: extra,
      pitchScore: pitchScore,
      rhythmScore: rhythmScore,
      overallScore: overallScore,
      duration: endTime.difference(startTime),
      evaluations: evaluations,
    );
  }

  double _calculateTimingAccuracy(int deviationMs) {
    if (deviationMs <= timingToleranceMs) {
      return 1.0;
    } else if (deviationMs <= timingToleranceMs * 2) {
      return 0.8;
    } else if (deviationMs <= timingToleranceMs * 3) {
      return 0.6;
    } else {
      return 0.4;
    }
  }
}
