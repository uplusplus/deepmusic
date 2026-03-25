import 'package:flutter/material.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/midi/pages/device_list_page.dart';
import '../../features/score/pages/score_library_page.dart';
import '../../features/score/pages/score_view_page.dart';
import '../../features/practice/pages/practice_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../../data/repositories/score_repository.dart';

class AppRouter {
  AppRouter._();

  static const String splash = '/';
  static const String home = '/home';
  static const String devices = '/devices';
  static const String scoreLibrary = '/scores';
  static const String scoreView = '/scores/:id';
  static const String practice = '/practice/:scoreId';
  static const String profile = '/profile';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => const SplashPage(),
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

// Placeholder pages
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pushReplacementNamed(AppRouter.home);
    });

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.piano,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            const Text(
              'DeepMusic',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your Music AI Assistant',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
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
      body: const Center(
        child: Text('Page not found'),
      ),
    );
  }
}
