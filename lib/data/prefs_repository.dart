import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Predefined auto-lock inactivity timeout intervals (§5.7).
enum AutoLockTimeout {
  seconds30(30, '30 seconds'),
  minute1(60, '1 minute'),
  minutes5(300, '5 minutes'),
  minutes15(900, '15 minutes'),
  never(0, 'Never');

  const AutoLockTimeout(this.seconds, this.label);
  final int seconds;
  final String label;

  static AutoLockTimeout fromSeconds(int seconds) {
    for (final val in values) {
      if (val.seconds == seconds) return val;
    }
    return AutoLockTimeout.minute1;
  }
}

/// Predefined clipboard auto-clear timeout intervals (§5.7).
enum ClipboardClearDelay {
  seconds15(15, '15 seconds'),
  seconds30(30, '30 seconds'),
  seconds60(60, '60 seconds'),
  never(0, 'Never');

  const ClipboardClearDelay(this.seconds, this.label);
  final int seconds;
  final String label;

  static ClipboardClearDelay fromSeconds(int seconds) {
    for (final val in values) {
      if (val.seconds == seconds) return val;
    }
    return ClipboardClearDelay.seconds30;
  }
}

/// Immutable non-secret user preferences model (§4.1, §5.6).
@immutable
class AppPrefs {
  const AppPrefs({
    this.themeMode = ThemeMode.system,
    this.autoLockTimeoutSeconds = 60,
    this.lockOnBackground = true,
    this.clipboardClearSeconds = 30,
  });

  final ThemeMode themeMode;
  final int autoLockTimeoutSeconds;
  final bool lockOnBackground;
  final int clipboardClearSeconds;

  AutoLockTimeout get autoLockTimeout =>
      AutoLockTimeout.fromSeconds(autoLockTimeoutSeconds);

  ClipboardClearDelay get clipboardClearDelay =>
      ClipboardClearDelay.fromSeconds(clipboardClearSeconds);

  AppPrefs copyWith({
    ThemeMode? themeMode,
    int? autoLockTimeoutSeconds,
    bool? lockOnBackground,
    int? clipboardClearSeconds,
  }) {
    return AppPrefs(
      themeMode: themeMode ?? this.themeMode,
      autoLockTimeoutSeconds:
          autoLockTimeoutSeconds ?? this.autoLockTimeoutSeconds,
      lockOnBackground: lockOnBackground ?? this.lockOnBackground,
      clipboardClearSeconds:
          clipboardClearSeconds ?? this.clipboardClearSeconds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppPrefs &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          autoLockTimeoutSeconds == other.autoLockTimeoutSeconds &&
          lockOnBackground == other.lockOnBackground &&
          clipboardClearSeconds == other.clipboardClearSeconds;

  @override
  int get hashCode => Object.hash(
    themeMode,
    autoLockTimeoutSeconds,
    lockOnBackground,
    clipboardClearSeconds,
  );

  @override
  String toString() =>
      'AppPrefs(themeMode: $themeMode, autoLockTimeoutSeconds: $autoLockTimeoutSeconds, lockOnBackground: $lockOnBackground, clipboardClearSeconds: $clipboardClearSeconds)';
}

/// Repository for persisting and retrieving non-sensitive user preferences (§5.6).
class PrefsRepository {
  PrefsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _themeModeKey = 'prefs_theme_mode';
  static const String _autoLockTimeoutKey = 'prefs_auto_lock_timeout';
  static const String _lockOnBackgroundKey = 'prefs_lock_on_background';
  static const String _clipboardClearSecondsKey = 'prefs_clipboard_clear_delay';

  /// Loads current [AppPrefs] with fallback to default values.
  AppPrefs load() {
    final themeString = _prefs.getString(_themeModeKey);
    final themeMode = switch (themeString) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final autoLockTimeout = _prefs.getInt(_autoLockTimeoutKey) ?? 60;
    final lockOnBackground = _prefs.getBool(_lockOnBackgroundKey) ?? true;
    final clipboardClear = _prefs.getInt(_clipboardClearSecondsKey) ?? 30;

    return AppPrefs(
      themeMode: themeMode,
      autoLockTimeoutSeconds: autoLockTimeout,
      lockOnBackground: lockOnBackground,
      clipboardClearSeconds: clipboardClear,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final str = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(_themeModeKey, str);
  }

  Future<void> setAutoLockTimeoutSeconds(int seconds) async {
    await _prefs.setInt(_autoLockTimeoutKey, seconds);
  }

  Future<void> setLockOnBackground(bool value) async {
    await _prefs.setBool(_lockOnBackgroundKey, value);
  }

  Future<void> setClipboardClearSeconds(int seconds) async {
    await _prefs.setInt(_clipboardClearSecondsKey, seconds);
  }

  Future<void> save(AppPrefs prefs) async {
    await setThemeMode(prefs.themeMode);
    await setAutoLockTimeoutSeconds(prefs.autoLockTimeoutSeconds);
    await setLockOnBackground(prefs.lockOnBackground);
    await setClipboardClearSeconds(prefs.clipboardClearSeconds);
  }
}

/// Provider for raw [SharedPreferences] instance. Must be overridden in root scope.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

/// Provider for [PrefsRepository].
final prefsRepositoryProvider = Provider<PrefsRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PrefsRepository(prefs);
});

/// Riverpod notifier managing reactive [AppPrefs] state.
class PrefsNotifier extends Notifier<AppPrefs> {
  @override
  AppPrefs build() {
    final repository = ref.watch(prefsRepositoryProvider);
    return repository.load();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await ref.read(prefsRepositoryProvider).setThemeMode(mode);
  }

  Future<void> setAutoLockTimeout(AutoLockTimeout timeout) =>
      setAutoLockTimeoutSeconds(timeout.seconds);

  Future<void> setAutoLockTimeoutSeconds(int seconds) async {
    state = state.copyWith(autoLockTimeoutSeconds: seconds);
    await ref.read(prefsRepositoryProvider).setAutoLockTimeoutSeconds(seconds);
  }

  Future<void> setLockOnBackground(bool value) async {
    state = state.copyWith(lockOnBackground: value);
    await ref.read(prefsRepositoryProvider).setLockOnBackground(value);
  }

  Future<void> setClipboardClearDelay(ClipboardClearDelay delay) =>
      setClipboardClearSeconds(delay.seconds);

  Future<void> setClipboardClearSeconds(int seconds) async {
    state = state.copyWith(clipboardClearSeconds: seconds);
    await ref.read(prefsRepositoryProvider).setClipboardClearSeconds(seconds);
  }

  Future<void> update(AppPrefs newPrefs) async {
    state = newPrefs;
    await ref.read(prefsRepositoryProvider).save(newPrefs);
  }
}

/// Global provider for [AppPrefs] state.
final prefsProvider = NotifierProvider<PrefsNotifier, AppPrefs>(
  PrefsNotifier.new,
);
