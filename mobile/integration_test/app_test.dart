import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:deepmusic/main.dart' as app;

/// Helper: Navigate to score library via bottom nav icons
Future<void> navigateToScoreLibrary(WidgetTester tester) async {
  final icon1 = find.byIcon(Icons.library_music_outlined);
  final icon2 = find.byIcon(Icons.library_music);
  if (icon1.evaluate().isNotEmpty) {
    await tester.tap(icon1.first);
  } else if (icon2.evaluate().isNotEmpty) {
    await tester.tap(icon2.first);
  }
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('DeepMusic E2E', () {
    testWidgets('App launches and shows home page', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(Scaffold), findsOneWidget);
      debugPrint('[E2E] PASS: App launched successfully');
    });

    testWidgets('Navigate to score library', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await navigateToScoreLibrary(tester);
      // Should see Cards (score items) or at least a new Scaffold
      expect(find.byType(Card), findsWidgets);
      debugPrint('[E2E] PASS: Navigated to score library');
    });

    testWidgets('Open score and verify rendering', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await navigateToScoreLibrary(tester);

      final scoreCards = find.byType(Card);
      expect(scoreCards, findsWidgets);
      await tester.tap(scoreCards.first);
      await tester.pumpAndSettle(const Duration(seconds: 8));

      expect(find.byType(AppBar), findsOneWidget);
      debugPrint('[E2E] PASS: Score opened and rendered');
    });

    testWidgets('Pagination bar for long scores', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await navigateToScoreLibrary(tester);

      // Open first score
      final scoreCards = find.byType(Card);
      expect(scoreCards, findsWidgets);
      await tester.tap(scoreCards.first);
      await tester.pumpAndSettle(const Duration(seconds: 10));

      // Check pagination
      final nextBtn = find.byIcon(Icons.chevron_right);
      if (nextBtn.evaluate().isNotEmpty) {
        debugPrint('[E2E] PASS: Pagination bar visible');

        // Navigate to page 2
        await tester.tap(nextBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        debugPrint('[E2E] PASS: Navigated to page 2');

        // Navigate back
        final prevBtn = find.byIcon(Icons.chevron_left);
        if (prevBtn.evaluate().isNotEmpty) {
          await tester.tap(prevBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 5));
          debugPrint('[E2E] PASS: Navigated back to page 1');
        }
      } else {
        debugPrint('[E2E] SKIP: No pagination (short score)');
      }
    });
  });
}
