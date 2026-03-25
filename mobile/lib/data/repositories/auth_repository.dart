import 'package:dio/dio.dart';
import '../services/api_client.dart';

/// 认证仓库
class AuthRepository {
  final ApiClient _apiClient;

  AuthRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// 注册
  Future<AuthResult> register({
    required String email,
    required String password,
    String? nickname,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          if (nickname != null) 'nickname': nickname,
        },
      );
      final data = response.data['data'];
      await _apiClient.saveToken(data['token']);
      return AuthResult.fromJson(data);
    } on DioException catch (e) {
      throw AuthException(e.message ?? '注册失败');
    }
  }

  /// 登录
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final data = response.data['data'];
      await _apiClient.saveToken(data['token']);
      return AuthResult.fromJson(data);
    } on DioException catch (e) {
      throw AuthException(e.message ?? '登录失败');
    }
  }

  /// 登出
  Future<void> logout() async {
    try {
      await _apiClient.dio.post('/auth/logout');
    } catch (_) {
      // 即使服务端登出失败，也清除本地 token
    }
    await _apiClient.clearToken();
  }

  /// 获取当前用户
  Future<UserInfo> getCurrentUser() async {
    try {
      final response = await _apiClient.dio.get('/auth/me');
      return UserInfo.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw AuthException(e.message ?? '获取用户信息失败');
    }
  }

  /// 更新用户信息
  Future<UserInfo> updateProfile({String? nickname, String? avatar}) async {
    try {
      final body = <String, dynamic>{};
      if (nickname != null) body['nickname'] = nickname;
      if (avatar != null) body['avatar'] = avatar;

      final response = await _apiClient.dio.patch('/auth/me', data: body);
      return UserInfo.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw AuthException(e.message ?? '更新失败');
    }
  }

  /// 检查是否有本地 token
  Future<bool> isLoggedIn() async {
    return (await _apiClient.getToken()) != null;
  }
}

// ── 数据模型 ──

class AuthResult {
  final UserInfo user;
  final String token;

  AuthResult({required this.user, required this.token});

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      user: UserInfo.fromJson(json['user']),
      token: json['token'],
    );
  }
}

class UserInfo {
  final String id;
  final String email;
  final String nickname;
  final String? avatar;
  final int totalPracticeTime;
  final int totalSessions;
  final int totalNotes;
  final DateTime createdAt;

  UserInfo({
    required this.id,
    required this.email,
    required this.nickname,
    this.avatar,
    required this.totalPracticeTime,
    required this.totalSessions,
    required this.totalNotes,
    required this.createdAt,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'],
      email: json['email'],
      nickname: json['nickname'] ?? json['email'].split('@')[0],
      avatar: json['avatar'],
      totalPracticeTime: json['totalPracticeTime'] ?? 0,
      totalSessions: json['totalSessions'] ?? 0,
      totalNotes: json['totalNotes'] ?? 0,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  /// 格式化总练习时长
  String get formattedPracticeTime {
    final hours = totalPracticeTime ~/ 3600;
    final minutes = (totalPracticeTime % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}
