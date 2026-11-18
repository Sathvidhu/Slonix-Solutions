import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CallBridge {
  static const _channel = MethodChannel('com.montme/calls');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static const _events = EventChannel('com.montme/callChanges');
  static dynamic _subscription;
  static void listen(VoidCallback callback) {
    _subscription = _events.receiveBroadcastStream().listen(
      (_) => callback(),
      onError: (_) {},
    );
  }

  static void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  static Future<String?> selectFolder() => const MethodChannel(
    'com.montme/files',
  ).invokeMethod<String>('selectFolder');
  static Future<List<Map<String, dynamic>>> recordings() async {
    final rows = await const MethodChannel(
      'com.montme/files',
    ).invokeListMethod<dynamic>('recordings');
    return (rows ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> read(DateTime since) async {
    if (!supported) {
      throw const FormatException(
        'Automatic import is available in the Android app.',
      );
    }
    final rows = await _channel.invokeListMethod<dynamic>('readCalls', {
      'since': since.millisecondsSinceEpoch,
    });
    return (rows ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }
}
