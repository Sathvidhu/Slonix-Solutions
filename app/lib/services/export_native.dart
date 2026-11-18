import 'package:flutter/services.dart';

Future<bool> saveExport(String name, String data, String mime) async =>
    await const MethodChannel('com.montme/files').invokeMethod<bool>('save', {
      'name': name,
      'data': data,
      'mime': mime,
      'base64': name.endsWith('.xlsx'),
    }) ??
    false;
