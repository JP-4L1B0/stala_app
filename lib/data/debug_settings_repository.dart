import 'package:shared_preferences/shared_preferences.dart';

class DebugSettingsRepository {
  static const String _debugEnabledKey = 'debug_page_enabled';

  const DebugSettingsRepository();

  Future<bool> isDebugPageEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debugEnabledKey) ?? false;
  }

  Future<void> setDebugPageEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debugEnabledKey, value);
  }
}