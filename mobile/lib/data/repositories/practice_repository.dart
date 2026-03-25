import 'dart:convert';
import 'package:dio/dio.dart';
import '../services/api_client.dart';

/// 练习仓库 — 封装练习相关 API
class PracticeRepository {
  final ApiClient _apiClient;

  PracticeRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  // ── 会话模式 (start → note → end) ──

  /// 开始练习会话
  Future<PracticeSessionStart> startSession(String scoreId) async {
    try {
      final response = await _apiClient.dio.post(
        '/practice/start',
        data: {'scoreId': scoreId},
      );
      return PracticeSessionStart.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw PracticeException(e.message ?? '开始练习失败');
    }
  }

  /// 批量上传音符事件
  Future<NoteUploadResult> uploadNotes(
    String sessionId,
    List<NoteEventData> notes,
  ) async {
    try {
      final response = await _apiClient.dio.post(
        '/practice/$sessionId/note',
        data: {
          'notes': notes.map((n) => n.toJson()).toList(),
        },
      );
      return NoteUploadResult.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw PracticeException(e.message ?? '上传音符失败');
    }
  }

  /// 结束练习会话
  Future<PracticeRecord> endSession(
    String sessionId, {
    required int duration,
    required int notesPlayed,
    required double pitchScore,
    required double rhythmScore,
    required double overallScore,
    required String grade,
    String? details,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/practice/$sessionId/end',
        data: {
          'duration': duration,
          'notesPlayed': notesPlayed,
          'pitchScore': pitchScore,
          'rhythmScore': rhythmScore,
          'overallScore': overallScore,
          'grade': grade,
          if (details != null) 'details': details,
        },
      );
      return PracticeRecord.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw PracticeException(e.message ?? '结束练习失败');
    }
  }

  // ── 直接模式 ──

  /// 直接创建练习记录
  Future<PracticeRecord> createRecord({
    required String scoreId,
    required int duration,
    required int notesPlayed,
    required double pitchScore,
    required double rhythmScore,
    required double overallScore,
    required String grade,
    String? details,
    required DateTime startedAt,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/practice',
        data: {
          'scoreId': scoreId,
          'duration': duration,
          'notesPlayed': notesPlayed,
          'pitchScore': pitchScore,
          'rhythmScore': rhythmScore,
          'overallScore': overallScore,
          'grade': grade,
          if (details != null) 'details': details,
          'startedAt': startedAt.toIso8601String(),
        },
      );
      return PracticeRecord.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw PracticeException(e.message ?? '创建记录失败');
    }
  }

  // ── 查询 ──

  /// 获取练习历史
  Future<PracticeListResult> getHistory({
    int page = 1,
    int limit = 20,
    String? scoreId,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/practice',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (scoreId != null) 'scoreId': scoreId,
        },
      );
      final data = response.data;
      final records = (data['data'] as List)
          .map((json) => PracticeRecord.fromJson(json))
          .toList();
      final pagination = data['pagination'];

      return PracticeListResult(
        records: records,
        page: pagination['page'],
        total: pagination['total'],
        totalPages: pagination['totalPages'],
      );
    } on DioException catch (e) {
      throw PracticeException(e.message ?? '获取练习历史失败');
    }
  }

  /// 获取统计数据
  Future<Map<String, dynamic>> getStats() async {
    try {
      final response = await _apiClient.dio.get('/practice/stats');
      return response.data['data'];
    } on DioException catch (e) {
      throw PracticeException(e.message ?? '获取统计数据失败');
    }
  }

  /// 获取单条记录
  Future<PracticeRecord> getRecord(String id) async {
    try {
      final response = await _apiClient.dio.get('/practice/$id');
      return PracticeRecord.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw PracticeException(e.message ?? '获取记录详情失败');
    }
  }

  /// 删除记录
  Future<void> deleteRecord(String id) async {
    try {
      await _apiClient.dio.delete('/practice/$id');
    } on DioException catch (e) {
      throw PracticeException(e.message ?? '删除记录失败');
    }
  }
}

// ── 数据模型 ──

class PracticeSessionStart {
  final String sessionId;
  final String scoreId;
  final Map<String, dynamic> score;
  final DateTime startedAt;

  PracticeSessionStart({
    required this.sessionId,
    required this.scoreId,
    required this.score,
    required this.startedAt,
  });

  factory PracticeSessionStart.fromJson(Map<String, dynamic> json) {
    return PracticeSessionStart(
      sessionId: json['sessionId'],
      scoreId: json['scoreId'],
      score: json['score'] ?? {},
      startedAt: DateTime.parse(json['startedAt']),
    );
  }
}

class NoteEventData {
  final int noteNumber;
  final int velocity;
  final String type;
  final DateTime timestamp;

  NoteEventData({
    required this.noteNumber,
    required this.velocity,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'noteNumber': noteNumber,
        'velocity': velocity,
        'type': type,
        'timestamp': timestamp.toIso8601String(),
      };
}

class NoteUploadResult {
  final int accepted;
  final int totalEvents;

  NoteUploadResult({required this.accepted, required this.totalEvents});

  factory NoteUploadResult.fromJson(Map<String, dynamic> json) {
    return NoteUploadResult(
      accepted: json['accepted'],
      totalEvents: json['totalEvents'],
    );
  }
}

class PracticeRecord {
  final String id;
  final String scoreId;
  final int duration;
  final int notesPlayed;
  final double pitchScore;
  final double rhythmScore;
  final double overallScore;
  final String grade;
  final String? details;
  final DateTime startedAt;
  final DateTime completedAt;
  final Map<String, dynamic>? score;

  PracticeRecord({
    required this.id,
    required this.scoreId,
    required this.duration,
    required this.notesPlayed,
    required this.pitchScore,
    required this.rhythmScore,
    required this.overallScore,
    required this.grade,
    this.details,
    required this.startedAt,
    required this.completedAt,
    this.score,
  });

  factory PracticeRecord.fromJson(Map<String, dynamic> json) {
    return PracticeRecord(
      id: json['id'],
      scoreId: json['scoreId'],
      duration: json['duration'],
      notesPlayed: json['notesPlayed'],
      pitchScore: (json['pitchScore'] as num).toDouble(),
      rhythmScore: (json['rhythmScore'] as num).toDouble(),
      overallScore: (json['overallScore'] as num).toDouble(),
      grade: json['grade'],
      details: json['details'],
      startedAt: DateTime.parse(json['startedAt']),
      completedAt: DateTime.parse(json['completedAt']),
      score: json['score'],
    );
  }
}

class PracticeListResult {
  final List<PracticeRecord> records;
  final int page;
  final int total;
  final int totalPages;

  PracticeListResult({
    required this.records,
    required this.page,
    required this.total,
    required this.totalPages,
  });
}

class PracticeException implements Exception {
  final String message;
  PracticeException(this.message);
  @override
  String toString() => message;
}
