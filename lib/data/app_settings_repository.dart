import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsRepository {
  static const String _autoSaveEnabledKey = 'auto_save_enabled';
  static const String _autoSaveToCloudKey = 'auto_save_to_cloud';
  static const String _saveFormatKey = 'save_format';
  static const String _recentFileLimitKey = 'recent_file_limit';
  static const String _tablatureExportOrientationKey =
      'tablature_export_orientation';
  static const int minimumRecentFileLimit = 3;

  const AppSettingsRepository();

  Future<bool> getAutoSaveEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSaveEnabledKey) ?? true;
  }

  Future<void> setAutoSaveEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSaveEnabledKey, value);
  }

  Future<bool> getAutoSaveToCloud() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSaveToCloudKey) ?? false;
  }

  Future<void> setAutoSaveToCloud(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSaveToCloudKey, value);
  }

  Future<String> getSaveFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_saveFormatKey) ?? 'stala';
  }

  Future<void> setSaveFormat(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saveFormatKey, value);
  }

  Future<int> getRecentFileLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_recentFileLimitKey) ?? minimumRecentFileLimit;
    return value < minimumRecentFileLimit ? minimumRecentFileLimit : value;
  }

  Future<void> setRecentFileLimit(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedValue = value < minimumRecentFileLimit
        ? minimumRecentFileLimit
        : value;
    await prefs.setInt(_recentFileLimitKey, normalizedValue);
  }

  Future<String> getTablatureExportOrientation() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_tablatureExportOrientationKey);
    return value == 'landscape' ? 'landscape' : 'portrait';
  }

  Future<void> setTablatureExportOrientation(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tablatureExportOrientationKey,
      value == 'landscape' ? 'landscape' : 'portrait',
    );
  }
}
