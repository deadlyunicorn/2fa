import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/data/prefs_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PrefsRepository & AppPrefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('default preferences when storage is empty', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsRepository(prefs);
      final loaded = repo.load();

      expect(loaded.themeMode, equals(ThemeMode.system));
      expect(loaded.autoLockTimeoutSeconds, equals(60));
      expect(loaded.autoLockTimeout, equals(AutoLockTimeout.minute1));
      expect(loaded.lockOnBackground, isTrue);
      expect(loaded.clipboardClearSeconds, equals(30));
      expect(loaded.clipboardClearDelay, equals(ClipboardClearDelay.seconds30));
    });

    test('loads pre-existing values correctly', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'prefs_theme_mode': 'dark',
        'prefs_auto_lock_timeout': 300,
        'prefs_lock_on_background': false,
        'prefs_clipboard_clear_delay': 15,
      });

      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsRepository(prefs);
      final loaded = repo.load();

      expect(loaded.themeMode, equals(ThemeMode.dark));
      expect(loaded.autoLockTimeoutSeconds, equals(300));
      expect(loaded.autoLockTimeout, equals(AutoLockTimeout.minutes5));
      expect(loaded.lockOnBackground, isFalse);
      expect(loaded.clipboardClearSeconds, equals(15));
      expect(loaded.clipboardClearDelay, equals(ClipboardClearDelay.seconds15));
    });

    test('repository individual setters persist to storage', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsRepository(prefs);

      await repo.setThemeMode(ThemeMode.light);
      expect(prefs.getString('prefs_theme_mode'), equals('light'));
      expect(repo.load().themeMode, equals(ThemeMode.light));

      await repo.setAutoLockTimeoutSeconds(900);
      expect(prefs.getInt('prefs_auto_lock_timeout'), equals(900));
      expect(repo.load().autoLockTimeout, equals(AutoLockTimeout.minutes15));

      await repo.setLockOnBackground(false);
      expect(prefs.getBool('prefs_lock_on_background'), isFalse);
      expect(repo.load().lockOnBackground, isFalse);

      await repo.setClipboardClearSeconds(60);
      expect(prefs.getInt('prefs_clipboard_clear_delay'), equals(60));
      expect(
        repo.load().clipboardClearDelay,
        equals(ClipboardClearDelay.seconds60),
      );
    });

    test('repository save() persists full model', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsRepository(prefs);

      const custom = AppPrefs(
        themeMode: ThemeMode.dark,
        autoLockTimeoutSeconds: 0,
        lockOnBackground: false,
        clipboardClearSeconds: 0,
      );

      await repo.save(custom);
      expect(repo.load(), equals(custom));
      expect(repo.load().autoLockTimeout, equals(AutoLockTimeout.never));
      expect(
        repo.load().clipboardClearDelay,
        equals(ClipboardClearDelay.never),
      );
    });

    test('AutoLockTimeout and ClipboardClearDelay enum helpers', () {
      expect(
        AutoLockTimeout.fromSeconds(30),
        equals(AutoLockTimeout.seconds30),
      );
      expect(AutoLockTimeout.fromSeconds(60), equals(AutoLockTimeout.minute1));
      expect(
        AutoLockTimeout.fromSeconds(300),
        equals(AutoLockTimeout.minutes5),
      );
      expect(
        AutoLockTimeout.fromSeconds(900),
        equals(AutoLockTimeout.minutes15),
      );
      expect(AutoLockTimeout.fromSeconds(0), equals(AutoLockTimeout.never));
      // Unknown fallback
      expect(
        AutoLockTimeout.fromSeconds(12345),
        equals(AutoLockTimeout.minute1),
      );

      expect(
        ClipboardClearDelay.fromSeconds(15),
        equals(ClipboardClearDelay.seconds15),
      );
      expect(
        ClipboardClearDelay.fromSeconds(30),
        equals(ClipboardClearDelay.seconds30),
      );
      expect(
        ClipboardClearDelay.fromSeconds(60),
        equals(ClipboardClearDelay.seconds60),
      );
      expect(
        ClipboardClearDelay.fromSeconds(0),
        equals(ClipboardClearDelay.never),
      );
      // Unknown fallback
      expect(
        ClipboardClearDelay.fromSeconds(999),
        equals(ClipboardClearDelay.seconds30),
      );
    });
  });

  group('prefsProvider & PrefsNotifier via Riverpod', () {
    late SharedPreferences prefs;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('reads initial state', () {
      final state = container.read(prefsProvider);
      expect(state.themeMode, equals(ThemeMode.system));
      expect(state.autoLockTimeoutSeconds, equals(60));
      expect(state.lockOnBackground, isTrue);
      expect(state.clipboardClearSeconds, equals(30));
    });

    test('mutations update both state and SharedPreferences', () async {
      final notifier = container.read(prefsProvider.notifier);

      await notifier.setThemeMode(ThemeMode.dark);
      expect(container.read(prefsProvider).themeMode, equals(ThemeMode.dark));
      expect(prefs.getString('prefs_theme_mode'), equals('dark'));

      await notifier.setAutoLockTimeout(AutoLockTimeout.seconds30);
      expect(container.read(prefsProvider).autoLockTimeoutSeconds, equals(30));
      expect(prefs.getInt('prefs_auto_lock_timeout'), equals(30));

      await notifier.setLockOnBackground(false);
      expect(container.read(prefsProvider).lockOnBackground, isFalse);
      expect(prefs.getBool('prefs_lock_on_background'), isFalse);

      await notifier.setClipboardClearDelay(ClipboardClearDelay.seconds15);
      expect(container.read(prefsProvider).clipboardClearSeconds, equals(15));
      expect(prefs.getInt('prefs_clipboard_clear_delay'), equals(15));
    });

    test('update() replaces entire prefs model', () async {
      final notifier = container.read(prefsProvider.notifier);
      const newPrefs = AppPrefs(
        themeMode: ThemeMode.light,
        autoLockTimeoutSeconds: 0,
        lockOnBackground: false,
        clipboardClearSeconds: 60,
      );

      await notifier.update(newPrefs);
      expect(container.read(prefsProvider), equals(newPrefs));
      expect(prefs.getString('prefs_theme_mode'), equals('light'));
      expect(prefs.getInt('prefs_auto_lock_timeout'), equals(0));
      expect(prefs.getBool('prefs_lock_on_background'), isFalse);
      expect(prefs.getInt('prefs_clipboard_clear_delay'), equals(60));
    });
  });
}
