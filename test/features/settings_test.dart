import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offline2fa/data/prefs_repository.dart';
import 'package:offline2fa/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone M9 — SettingsScreen Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'prefs_theme_mode': 'system',
        'prefs_auto_lock_timeout': 60,
        'prefs_lock_on_background': true,
        'prefs_clipboard_clear_delay': 30,
      });
      prefs = await SharedPreferences.getInstance();
    });

    Widget createTestWidget({
      required ProviderContainer container,
      GoRouter? router,
    }) {
      if (router != null) {
        return UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        );
      }

      return UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      );
    }

    testWidgets('renders all sections and initial default values', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestWidget(container: container));
      await tester.pumpAndSettle();

      // Headers
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Security & Privacy'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);

      // Theme
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Security & Privacy defaults
      expect(find.text('Auto-lock timeout'), findsOneWidget);
      expect(find.text('1 minute'), findsOneWidget);

      expect(find.text('Lock when app goes to background'), findsOneWidget);
      final switchFinder = find.byKey(
        const Key('settings_lock_on_background_tile'),
      );
      expect(switchFinder, findsOneWidget);
      final switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isTrue);

      expect(find.text('Clipboard auto-clear delay'), findsOneWidget);
      expect(find.text('30 seconds'), findsOneWidget);

      expect(find.text('Change Master Password'), findsOneWidget);
      expect(find.text('Backup & Restore'), findsOneWidget);

      // About
      expect(
        find.text(
          'This app has no internet access. Your 2FA secrets never leave your device.',
        ),
        findsOneWidget,
      );
      expect(find.text('Offline 2FA'), findsOneWidget);
      expect(
        find.text('Version 0.1.0+1 • License: GPL-3.0-only'),
        findsOneWidget,
      );
      expect(find.text('Open-source licenses'), findsOneWidget);
    });

    testWidgets('switches theme between System, Light, and Dark', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestWidget(container: container));
      await tester.pumpAndSettle();

      expect(container.read(prefsProvider).themeMode, equals(ThemeMode.system));

      // Switch to Light
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(container.read(prefsProvider).themeMode, equals(ThemeMode.light));

      // Switch to Dark
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(container.read(prefsProvider).themeMode, equals(ThemeMode.dark));

      // Switch back to System
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(container.read(prefsProvider).themeMode, equals(ThemeMode.system));
    });

    testWidgets('changes auto-lock timeout via dialog', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestWidget(container: container));
      await tester.pumpAndSettle();

      expect(container.read(prefsProvider).autoLockTimeoutSeconds, equals(60));

      // Tap Auto-lock timeout tile
      await tester.tap(find.byKey(const Key('settings_auto_lock_tile')));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Auto-lock timeout'), findsWidgets);
      expect(find.text('30 seconds'), findsWidgets);
      expect(find.text('5 minutes'), findsOneWidget);
      expect(find.text('15 minutes'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);

      // Select '5 minutes'
      await tester.tap(find.byKey(const Key('autolock_option_300')));
      await tester.pumpAndSettle();

      expect(container.read(prefsProvider).autoLockTimeoutSeconds, equals(300));
      expect(find.text('5 minutes'), findsOneWidget);
    });

    testWidgets('toggles lock on background switch', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestWidget(container: container));
      await tester.pumpAndSettle();

      expect(container.read(prefsProvider).lockOnBackground, isTrue);

      // Tap switch tile
      await tester.tap(
        find.byKey(const Key('settings_lock_on_background_tile')),
      );
      await tester.pumpAndSettle();

      expect(container.read(prefsProvider).lockOnBackground, isFalse);

      // Tap again to enable
      await tester.tap(
        find.byKey(const Key('settings_lock_on_background_tile')),
      );
      await tester.pumpAndSettle();

      expect(container.read(prefsProvider).lockOnBackground, isTrue);
    });

    testWidgets('changes clipboard auto-clear delay via dialog', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestWidget(container: container));
      await tester.pumpAndSettle();

      expect(container.read(prefsProvider).clipboardClearSeconds, equals(30));

      // Tap Clipboard clear delay tile
      await tester.tap(find.byKey(const Key('settings_clipboard_clear_tile')));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Clipboard auto-clear delay'), findsWidgets);
      expect(find.text('15 seconds'), findsOneWidget);
      expect(find.text('60 seconds'), findsOneWidget);

      // Select '60 seconds'
      await tester.tap(find.byKey(const Key('clipboard_option_60')));
      await tester.pumpAndSettle();

      expect(container.read(prefsProvider).clipboardClearSeconds, equals(60));
      expect(find.text('60 seconds'), findsOneWidget);
    });

    testWidgets('navigates to change master password and backup', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/settings/change-password',
            builder: (context, state) =>
                const Scaffold(body: Text('Change Password Screen Target')),
          ),
          GoRoute(
            path: '/backup',
            builder: (context, state) =>
                const Scaffold(body: Text('Backup Screen Target')),
          ),
        ],
      );

      await tester.pumpWidget(
        createTestWidget(container: container, router: router),
      );
      await tester.pumpAndSettle();

      // Navigate to Change Password
      await tester.tap(find.byKey(const Key('settings_change_password_tile')));
      await tester.pumpAndSettle();
      expect(find.text('Change Password Screen Target'), findsOneWidget);

      // Pop back
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      // Navigate to Backup & Restore
      await tester.tap(find.byKey(const Key('settings_backup_tile')));
      await tester.pumpAndSettle();
      expect(find.text('Backup Screen Target'), findsOneWidget);
    });

    testWidgets('tapping Open-source licenses opens license page', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestWidget(container: container));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_licenses_tile')),
        200,
      );
      await tester.tap(find.byKey(const Key('settings_licenses_tile')));
      await tester.pumpAndSettle();

      // License page displays application name and licenses
      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text('Offline 2FA'), findsWidgets);
    });
  });
}
