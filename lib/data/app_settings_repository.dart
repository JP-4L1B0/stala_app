import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsRepository {
  static const String _autoSaveEnabledKey = 'auto_save_enabled';
  static const String _autoSaveToCloudKey = 'auto_save_to_cloud';
  static const String _saveFormatKey = 'save_format';

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
}