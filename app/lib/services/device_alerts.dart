import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceAlerts {
  static const channel = MethodChannel('com.montme/alerts');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<Map<String, dynamic>> status() async {
    if (!supported) return {'allowed': false};
    try {
      return Map<String, dynamic>.from(
        await channel.invokeMethod('status') as Map,
      );
    } catch (_) {
      return {'allowed': false};
    }
  }

  static Future<void> permission() async {
    if (supported) await channel.invokeMethod('permission');
  }

  static Future<void> show(String key, String title, String body) async {
    if (supported) {
      await channel.invokeMethod('show', {
        'key': key,
        'title': title,
        'body': body,
      });
    }
  }

  static Future<void> schedule(
    String key,
    String title,
    String body,
    DateTime at,
  ) async {
    if (supported) {
      await channel.invokeMethod('schedule', {
        'key': key,
        'title': title,
        'body': body,
        'at': at.millisecondsSinceEpoch,
      });
    }
  }

  static Future<void> cancel(String key) async {
    if (supported) await channel.invokeMethod('cancel', {'key': key});
  }

  static Future<void> clear({bool dismissNotifications = false}) async {
    if (supported) {
      await channel.invokeMethod('clear', {'dismiss': dismissNotifications});
    }
  }

  static Future<String?> configurePush(Map<String, dynamic> config) async =>
      supported
      ? await channel.invokeMethod<String>('configurePush', {'config': config})
      : null;
}
