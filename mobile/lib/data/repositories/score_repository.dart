import 'package:dio/dio.dart';
import '../models/score.dart';
import '../../core/constants/app_colors.dart';
import 'api_client.dart';

class ScoreRepository {
  final ApiClient _apiClient;

  ScoreRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// 获取乐谱列表
  Future<ScoreListResult> getScores({
    int page = 1,
    int limit = 20,
    String? difficulty,
    String? category,
    String? search,
  }) async {
    try {
      final response = await _apiClient.dio.get('/scores', queryParameters: {
        'page': page,
        'limit': limit,
        if (difficulty != null) 'difficulty': difficulty,
        if (category != null) 'category': category,
        if (search != null) 'search': search,
      });

      final data = response.data;
      final scores = (data['data'] as List)
          .map((json) => ScoreModel.fromJson(json))
          .toList();
      final pagination = data['pagination'];

      return ScoreListResult(
        scores: scores,
        page: pagination['page'],
        limit: pagination['limit'],
        total: pagination['total'],
        totalPages: pagination['totalPages'],
      );
    } on DioException catch (e) {
      throw ScoreException(e.message ?? '获取乐谱列表失败');
    }
  }

  /// 获取推荐乐谱
  Future<List<ScoreModel>> getRecommendedScores({int limit = 10}) async {
    try {
      final response = await _apiClient.dio.get(
        '/scores/recommended',
        queryParameters: {'limit': limit},
      );

      return (response.data['data'] as List)
          .map((json) => ScoreModel.fromJson(json))
          .toList();
    } on DioException catch (e) {
      throw ScoreException(e.message ?? '获取推荐乐谱失败');
    }
  }

  /// 搜索乐谱
  Future<List<ScoreModel>> searchScores(String query) async {
    try {
      final response = await _apiClient.dio.get(
        '/scores/search',
        queryParameters: {'q': query},
      );

      return (response.data['data'] as List)
          .map((json) => ScoreModel.fromJson(json))
          .toList();
    } on DioException catch (e) {
      throw ScoreException(e.message ?? '搜索乐谱失败');
    }
  }

  /// 获取单个乐谱
  Future<ScoreModel> getScoreById(String id) async {
    try {
      final response = await _apiClient.dio.get('/scores/$id');
      return ScoreModel.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw ScoreException(e.message ?? '获取乐谱失败');
    }
  }

  /// 下载乐谱文件
  Future<String> downloadScoreFile(String scoreId, String savePath) async {
    try {
      await _apiClient.dio.download(
        '/scores/$scoreId/xml',
        savePath,
      );
      return savePath;
    } on DioException catch (e) {
      throw ScoreException(e.message ?? '下载乐谱失败');
    }
  }

  /// 获取乐谱 MusicXML 内容 (用于渲染)
  Future<String> getScoreXml(String scoreId) async {
    try {
      final response = await _apiClient.dio.get(
        '/scores/$scoreId/xml',
        options: Options(responseType: ResponseType.plain),
      );
      return response.data as String;
    } on DioException catch (e) {
      throw ScoreException(e.message ?? '获取乐谱文件失败');
    }
  }

  /// 收藏乐谱
  Future<void> favoriteScore(String scoreId) async {
    try {
      await _apiClient.dio.post('/scores/$scoreId/favorite');
    } on DioException catch (e) {
      throw ScoreException(e.message ?? '收藏失败');
    }
  }

  /// 取消收藏
  Future<void> unfavoriteScore(String scoreId) async {
    try {
      await _apiClient.dio.delete('/scores/$scoreId/favorite');
    } on DioException catch (e) {
      throw ScoreException(e.message ?? '取消收藏失败');
    }
  }
}

/// 乐谱模型 (API 响应)
class ScoreModel {
  final String id;
  final String title;
  final String composer;
  final String? arranger;
  final String difficulty;
  final String? category;
  final int duration;
  final int measures;
  final String timeSignature;
  final String keySignature;
  final int tempo;
  final String? coverImage;
  final String musicXmlPath;
  final int playCount;
  final int favoriteCount;
  final String? source;
  final String? license;
  final DateTime createdAt;

  ScoreModel({
    required this.id,
    required this.title,
    required this.composer,
    this.arranger,
    required this.difficulty,
    this.category,
    required this.duration,
    required this.measures,
    required this.timeSignature,
    required this.keySignature,
    required this.tempo,
    this.coverImage,
    required this.musicXmlPath,
    required this.playCount,
    required this.favoriteCount,
    this.source,
    this.license,
    required this.createdAt,
  });

  factory ScoreModel.fromJson(Map<String, dynamic> json) {
    return ScoreModel(
      id: json['id'],
      title: json['title'],
      composer: json['composer'],
      arranger: json['arranger'],
      difficulty: json['difficulty'],
      category: json['category'],
      duration: json['duration'],
      measures: json['measures'],
      timeSignature: json['timeSignature'],
      keySignature: json['keySignature'],
      tempo: json['tempo'],
      coverImage: json['coverImage'],
      musicXmlPath: json['musicXmlPath'],
      playCount: json['playCount'] ?? 0,
      favoriteCount: json['favoriteCount'] ?? 0,
      source: json['source'],
      license: json['license'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  /// 难度颜色
  Color get difficultyColor {
    switch (difficulty) {
      case 'BEGINNER':
        return AppColors.success;
      case 'INTERMEDIATE':
        return AppColors.warning;
      case 'ADVANCED':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  /// 难度文本
  String get difficultyText {
    switch (difficulty) {
      case 'BEGINNER':
        return '初级';
      case 'INTERMEDIATE':
        return '中级';
      case 'ADVANCED':
        return '高级';
      default:
        return difficulty;
    }
  }

  /// 格式化时长
  String get formattedDuration {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 乐谱列表结果
class ScoreListResult {
  final List<ScoreModel> scores;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  ScoreListResult({
    required this.scores,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  bool get hasMore => page < totalPages;
}

/// 乐谱异常
class ScoreException implements Exception {
  final String message;
  ScoreException(this.message);

  @override
  String toString() => message;
}
