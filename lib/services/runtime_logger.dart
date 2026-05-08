import 'package:flutter/services.dart';

class RuntimeLogger {
  static const MethodChannel _channel = MethodChannel('stala/python_bridge');

  static Future<void> log(String message) async {
    try {
      await _channel.invokeMethod('appendRuntimeLog', {
        'message': message,
      });
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await _channel.invokeMethod('clearRuntimeLog');
    } catch (_) {}
  }

  static Future<String?> export() async {
    try {
      final result = await _channel.invokeMethod('exportRuntimeLog');

      if (result is Map && result['status'] == 'success') {
        return result['path']?.toString();
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}