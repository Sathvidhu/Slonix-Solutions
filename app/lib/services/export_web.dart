import 'dart:js_interop';
import 'dart:convert';
import 'package:web/web.dart' as web;

Future<bool> saveExport(String name, String data, String mime) async {
  final blob = web.Blob(
    [name.endsWith('.xlsx') ? base64Decode(data).toJS : data.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Allow the browser time to consume the object URL before releasing it.
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
  return true;
}
