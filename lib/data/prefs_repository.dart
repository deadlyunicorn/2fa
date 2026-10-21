import 'package:shared_preferences/shared_preferences.dart';

/// Repository for non-sensitive user preferences.
class PrefsRepository {
  PrefsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _themeKey = 'prefs_theme_mode';
  static const String _autoLockTimeoutKey = 'prefs_auto_lock_timeout';
  static const String _lockOnBackgroundKey = 'prefs_lock_on_background';
  static const String _clipboardClearDelayKey = 'prefs_clipboard_clear_delay';

  String get themeMode => _prefs.getString(_themeKey) ?? 'system';
  Future<void> setThemeMode(String value) => _prefs.setString(_themeKey, value);

  int get autoLockTimeoutSeconds => _prefs.getInt(_autoLockTimeoutKey) ?? 60;
  Future<void> setAutoLockTimeoutSeconds(int value) =>
      _prefs.setInt(_autoLockTimeoutKey, value);

  bool get lockOnBackground => _prefs.getBool(_lockOnBackgroundKey) ?? true;
  Future<void> setLockOnBackground(bool value) =>
      _prefs.setBool(_lockOnBackgroundKey, value);

  int get clipboardClearDelaySeconds =>
      _prefs.getInt(_clipboardClearDelayKey) ?? 30;
  Future<void> setClipboardClearDelaySeconds(int value) =>
      _prefs.setInt(_clipboardClearDelayKey, value);
}
