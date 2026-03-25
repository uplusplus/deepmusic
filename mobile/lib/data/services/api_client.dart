import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  String? _token;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://192.168.43.175:3000/api',
        ),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'X-Client': 'deepmusic-mobile/1.0',
        },
      ),
    );

    // 请求拦截器: 自动附加 token
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // 标记请求开始时间
          options.extra['_startTime'] = DateTime.now().millisecondsSinceEpoch;
          _logRequest(options);
          return handler.next(options);
        },
        onResponse: (response, responseHandler) {
          _logResponse(response);
          return responseHandler.next(response);
        },
        onError: (error, handler) {
          _logError(error);
          final message = _getErrorMessage(error);
          error = error.copyWith(message: message);
          return handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  // ── Token 管理 ──

  Future<String?> getToken() async {
    _token ??= (await SharedPreferences.getInstance()).getString('auth_token');
    return _token;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  // ── 错误处理 ──

  String _getErrorMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查网络';
      case DioExceptionType.sendTimeout:
        return '发送超时，请检查网络';
      case DioExceptionType.receiveTimeout:
        return '接收超时，请检查网络';
      case DioExceptionType.badResponse:
        final data = error.response?.data;
        if (data is Map && data['error'] != null) {
          return data['error'];
        }
        return '服务器错误 (${error.response?.statusCode})';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.connectionError:
        return '网络连接失败';
      default:
        return '未知错误';
    }
  }

  // ── API 日志 ──

  void _logRequest(RequestOptions options) {
    final uri = options.uri;
    final path = uri.path;
    final method = options.method;
    final hasBody = options.data != null;
    print('[API] → $method $path${hasBody ? " (${_getBodySize(options.data)} bytes)" : ""}');
  }

  void _logResponse(Response response) {
    final req = response.requestOptions;
    final path = req.uri.path;
    final method = req.method;
    final status = response.statusCode;
    final startTime = req.extra['_startTime'] as int?;
    final elapsed = startTime != null
        ? '${DateTime.now().millisecondsSinceEpoch - startTime}ms'
        : '?';
    final size = response.data != null ? _getResponseSummary(response.data) : '';
    print('[API] ← $method $path $status $elapsed $size');
  }

  void _logError(DioException error) {
    final req = error.requestOptions;
    final path = req.uri.path;
    final method = req.method;
    final status = error.response?.statusCode ?? 'ERR';
    final startTime = req.extra['_startTime'] as int?;
    final elapsed = startTime != null
        ? '${DateTime.now().millisecondsSinceEpoch - startTime}ms'
        : '?';
    print('[API] ✗ $method $path $status $elapsed ${error.message}');
  }

  String _getBodySize(dynamic data) {
    if (data == null) return '0';
    if (data is String) return data.length.toString();
    if (data is Map || data is List) return data.toString().length.toString();
    return '?';
  }

  String _getResponseSummary(dynamic data) {
    if (data is Map) {
      if (data['data'] is List) {
        final list = data['data'] as List;
        return '(${list.length} items)';
      }
      if (data['data'] is Map) return '(object)';
      if (data['success'] != null) return '(ok)';
    }
    if (data is List) return '(${data.length} items)';
    return '';
  }

}