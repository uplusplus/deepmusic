import 'package:flutter/material.dart';
import '../../features/auth/pages/auth_page.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/midi/pages/device_list_page.dart';
import '../../features/score/pages/score_library_page.dart';
import '../../features/score/pages/score_view_page.dart';
import '../../features/practice/pages/practice_page.dart';
import '../../features/practice/pages/practice_history_page.dart';
import '../../features/practice/pages/statistics_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../../data/repositories/auth_repository.dart';

class AppRouter {
  AppRouter._();

  static const String splash = '/';
  static const String auth = '/auth';
  static const String home = '/home';
  static const String devices = '/devices';
  static const String scoreLibrary = '/scores';
  static const String scoreView = '/scores/:id';
  static const String practice = '/practice/:scoreId';
  static const String practiceHistory = '/practice-history';
  static const String statistics = '/statistics';
  static const String profile = '/profile';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => const SplashPage(),
          settings: settings,
        );
      case auth:
        return MaterialPageRoute(
          builder: (_) => const AuthPage(),
          settings: settings,
        );
      case home:
        return MaterialPageRoute(
          builder: (_) => const HomePage(),
          settings: settings,
        );
      case devices:
        return MaterialPageRoute(
          builder: (_) => const DeviceListPage(),
          settings: settings,
        );
      case scoreLibrary:
        return MaterialPageRoute(
          builder: (_) => const ScoreLibraryPage(),
          settings: settings,
        );
      case scoreView:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => ScoreViewPage(
            scoreId: args?['id'] ?? '',
          ),
          settings: settings,
        );
      case practice:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => PracticePage(
            scoreId: args?['scoreId'] ?? '',
          ),
          settings: settings,
        );
      case practiceHistory:
        return MaterialPageRoute(
          builder: (_) => const PracticeHistoryPage(),
          settings: settings,
        );
      case statistics:
        return MaterialPageRoute(
          builder: (_) => const StatisticsPage(),
          settings: settings,
        );
      case profile:
        return MaterialPageRoute(
          builder: (_) => const ProfilePage(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const NotFoundPage(),
          settings: settings,
        );
    }
  }
}

/// 启动页 — 检查登录状态后跳转
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // 最少显示 1.5 秒启动画面
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    final authRepo = AuthRepository();
    final hasToken = await authRepo.isLoggedIn();

    if (!hasToken) {
      // 没有本地 token → 登录页
      if (mounted) Navigator.of(context).pushReplacementNamed(AppRouter.auth);
      return;
    }

    // 有本地 token → 尝试验证（联网校验 token 是否仍然有效）
    try {
      await authRepo.getCurrentUser();
      if (mounted) Navigator.of(context).pushReplacementNamed(AppRouter.home);
    } on AuthException catch (_) {
      // token 无效/过期 → 清除本地 token，跳转登录页
      await authRepo.logout();
      if (mounted) Navigator.of(context).pushReplacementNamed(AppRouter.auth);
    } catch (_) {
      // 网络错误 → 信任本地 token，允许离线进入
      if (mounted) Navigator.of(context).pushReplacementNamed(AppRouter.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.piano, size: 80, color: Colors.white),
            SizedBox(height: 16),
            Text(
              'DeepMusic',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Your Music AI Assistant',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            SizedBox(height: 48),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not Found')),
      body: const Center(child: Text('Page not found')),
    );
  }
}
