import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AttendanceUnavailable implements Exception {
  const AttendanceUnavailable();

  @override
  String toString() =>
      'Clock-in and clock-out are unavailable until your company updates its attendance server. Contact your admin.';
}

/// Uses public project configuration. RLS authorizes every company request.
class CompanyCloud {
  CompanyCloud({http.Client? client, this.persistSession = true})
    : _client = client ?? http.Client();
  final bool persistSession;
  static const _vault = FlutterSecureStorage();
  static const _sessionKey = 'montme.company.session.v2';
  String? userId;
  DateTime? _identityChecked;
  final http.Client _client;
  static const url = 'https://xnbqhzawxnjflhoskkds.supabase.co';
  static const key = 'sb_publishable__7Eu5E8UmMOlEpjVgYCcqw_8PRpRebs';
  String? _access, _refresh;
  DateTime? _expires;
  Map<String, dynamic>? employee;
  List<Map<String, dynamic>> assignments = [],
      content = [],
      receipts = [],
      contacts = [],
      notifications = [],
      notificationReceipts = [],
      exitRequests = [],
      submissions = [],
      shifts = [],
      syncedCalls = [];
  Map<String, dynamic> settings = {};
  DateTime? lastSync;
  String? error;
  bool get connected => employee != null && _access != null;

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    String? prefer,
    bool refresh = true,
  }) async {
    if (refresh &&
        _access != null &&
        _expires != null &&
        DateTime.now().isAfter(
          _expires!.subtract(const Duration(seconds: 30)),
        )) {
      final session = await request(
        '/auth/v1/token?grant_type=refresh_token',
        method: 'POST',
        body: {'refresh_token': _refresh},
        refresh: false,
      );
      await _session(Map<String, dynamic>.from(session as Map));
    }
    final response = http.Request(method, Uri.parse('$url$path'))
      ..headers.addAll({
        'apikey': key,
        'Authorization': 'Bearer ${_access ?? key}',
        'Content-Type': 'application/json',
      });
    if (prefer != null) {
      response.headers['Prefer'] = prefer;
    }
    if (body != null) response.body = jsonEncode(body);
    final result = await http.Response.fromStream(
      await _client.send(response).timeout(const Duration(seconds: 25)),
    ).timeout(const Duration(seconds: 25));
    if (result.statusCode >= 500) {
      throw StateError(
        'The company server is temporarily unavailable. Try again shortly.',
      );
    }
    final dynamic data;
    try {
      data = result.body.isEmpty ? null : jsonDecode(result.body);
    } on FormatException {
      throw StateError('The company server returned an unexpected response.');
    }
    if (result.statusCode >= 400) {
      if (data is Map &&
          data['code'] == 'PGRST202' &&
          const {
            '/rest/v1/rpc/clock_in',
            '/rest/v1/rpc/submit_daily_report',
            '/rest/v1/rpc/toggle_shift_break',
          }.contains(path)) {
        throw const AttendanceUnavailable();
      }
      throw StateError(
        result.statusCode == 404 && path.startsWith('/functions/')
            ? 'The account service is not deployed yet. Ask your admin to complete the server upgrade.'
            : data is Map
            ? (data['message'] ??
                      data['msg'] ??
                      data['error_description'] ??
                      'Company request failed.')
                  .toString()
            : 'Company request failed (${result.statusCode}).',
      );
    }
    return data;
  }

  Future<void> _session(Map<String, dynamic> session) async {
    _access = session['access_token'] as String;
    _refresh = session['refresh_token'] as String;
    userId = (session['user'] as Map?)?['id'] as String? ?? userId;
    final expires =
        (session['expires_at'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch ~/ 1000 +
            ((session['expires_in'] as num?)?.toInt() ?? 3600);
    _expires = DateTime.fromMillisecondsSinceEpoch(expires * 1000);
    if (persistSession) {
      await _vault.write(
        key: _sessionKey,
        value: jsonEncode({
          ...session,
          'expires_at': expires,
          'user': {'id': userId},
        }),
      );
    }
  }

  Future<void> _identify() async {
    final rows =
        await request(
              '/rest/v1/employees?select=*&auth_id=eq.$userId&active=eq.true',
            )
            as List;
    if (rows.isEmpty) {
      throw StateError(
        'This account is not an active employee. Ask your admin to check your employee ID and access.',
      );
    }
    employee = Map<String, dynamic>.from(rows.first as Map);
    _identityChecked = DateTime.now();
  }

  Future<Map<String, dynamic>> signIn(
    String employeeId,
    String password,
  ) async {
    final path = employeeId.contains('@')
        ? '/auth/v1/token?grant_type=password'
        : '/functions/v1/employee-login';
    final session = Map<String, dynamic>.from(
      await request(
            path,
            method: 'POST',
            body: {
              if (employeeId.contains('@'))
                'email': employeeId.trim()
              else
                'employee_id': employeeId.trim(),
              'password': password,
            },
          )
          as Map,
    );
    try {
      await _session(session);
      await _identify();
      return employee!;
    } catch (_) {
      await signOut();
      rethrow;
    }
  }

  Future<bool> restoreSession() async {
    if (!persistSession) return false;
    try {
      final raw = await _vault.read(key: _sessionKey);
      if (raw == null) return false;
      await _session(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      await request('/auth/v1/user');
      await _identify();
      return true;
    } catch (_) {
      await signOut();
      return false;
    }
  }

  Future<void> signOut() async {
    if (_access != null) {
      try {
        await request(
          '/auth/v1/logout?scope=local',
          method: 'POST',
          refresh: false,
        );
      } catch (_) {}
    }
    if (persistSession) await _vault.delete(key: _sessionKey);
    disconnect();
  }

  void disconnect() {
    employee = null;
    _access = null;
    _refresh = null;
    _expires = null;
    assignments = [];
    content = [];
    receipts = [];
    contacts = [];
    notifications = [];
    notificationReceipts = [];
    exitRequests = [];
    submissions = [];
    shifts = [];
    syncedCalls = [];
    settings = {};
    userId = null;
    lastSync = null;
    error = null;
  }

  Future<List<Map<String, dynamic>>> rows(String table) async =>
      (await request(
                '/rest/v1/$table?select=*&limit=5000${table == 'contacts'
                    ? '&assigned_employee_id=eq.${employee!['id']}'
                    : table == 'assignments'
                    ? '&recipient_ids=cs.{${employee!['id']}}'
                    : table == 'notifications'
                    ? '&audience=eq.employee&employee_id=eq.${employee!['id']}'
                    : (table == 'early_exit_requests' || table == 'work_submissions' || table == 'shift_records' || table == 'call_records')
                    ? '&employee_id=eq.${employee!['id']}'
                    : table == 'notification_receipts'
                    ? '&user_id=eq.$userId'
                    : ''}',
              )
              as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
  Future<void> fetchWork() async {
    if (_identityChecked != null &&
        DateTime.now().difference(_identityChecked!).inSeconds >= 60) {
      try {
        await _identify();
      } catch (_) {
        await signOut();
        rethrow;
      }
    }
    final results = await Future.wait([
      rows('assignments'),
      rows('content_items'),
      rows('assignment_receipts'),
      rows('contacts'),
      rows('notifications'),
      rows('notification_receipts'),
      rows('workspace_settings'),
      rows('early_exit_requests'),
      rows('work_submissions'),
      rows('shift_records'),
      rows('call_records'),
    ]);
    assignments = results[0]
      ..sort(
        (a, b) => DateTime.parse(
          b['release_at'] as String,
        ).compareTo(DateTime.parse(a['release_at'] as String)),
      );
    content = results[1];
    receipts = results[2];
    contacts = results[3];
    notifications = results[4]
      ..sort(
        (a, b) => DateTime.parse(
          b['available_at'] as String,
        ).compareTo(DateTime.parse(a['available_at'] as String)),
      );
    notificationReceipts = results[5];
    settings = results[6].firstOrNull ?? {};
    exitRequests = results[7];
    submissions = results[8];
    shifts = results[9];
    syncedCalls = results[10];
  }

  Future<void> upsert(
    String table,
    String conflict,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    for (var i = 0; i < rows.length; i += 100) {
      await request(
        '/rest/v1/$table?on_conflict=$conflict',
        method: 'POST',
        body: rows.sublist(i, (i + 100).clamp(0, rows.length)),
        prefer: 'resolution=merge-duplicates',
      );
    }
  }

  Future<void> acknowledge(String assignment, String status) => request(
    '/rest/v1/rpc/acknowledge_assignment',
    method: 'POST',
    body: {'assignment_id_input': assignment, 'status_input': status},
  );
  Future<void> markNotification(String id, bool read) => request(
    '/rest/v1/rpc/set_notification_read',
    method: 'POST',
    body: {'notification_input': id, 'read_input': read},
  );
  Future<void> registerPush(String token) => request(
    '/rest/v1/rpc/register_push_device',
    method: 'POST',
    body: {'token_input': token},
  );
  Future<void> unregisterPush(String token) => request(
    '/rest/v1/rpc/unregister_push_device',
    method: 'POST',
    body: {'token_input': token},
  );
  Future<void> uploadReport(
    String name,
    List<int> bytes, {
    String note = '',
  }) async {
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw StateError('Choose a non-empty file up to 20 MB.');
    }
    await request('/auth/v1/user');
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        '${employee!['id']}/${DateTime.now().microsecondsSinceEpoch}/$safe';
    final upload =
        http.Request(
            'POST',
            Uri.parse('$url/storage/v1/object/montme-submissions/$path'),
          )
          ..headers.addAll({
            'apikey': key,
            'Authorization': 'Bearer $_access',
            'Content-Type': 'application/octet-stream',
            'x-upsert': 'false',
          })
          ..bodyBytes = bytes;
    final response = await http.Response.fromStream(
      await _client.send(upload).timeout(const Duration(seconds: 60)),
    );
    if (response.statusCode >= 400) {
      throw StateError(
        'Report upload failed (${response.statusCode}). Retry after refreshing.',
      );
    }
    try {
      await request(
        '/rest/v1/work_submissions',
        method: 'POST',
        body: {
          'employee_id': employee!['id'],
          'file_path': path,
          'file_name': name,
          'mime_type': 'application/octet-stream',
          'size_bytes': bytes.length,
          'note': note,
        },
      );
    } catch (_) {
      try {
        await request(
          '/storage/v1/object/montme-submissions',
          method: 'DELETE',
          body: {
            'prefixes': [path],
          },
        );
      } catch (_) {}
      rethrow;
    }
  }

  Future<String> signedFile(String path) async {
    final data =
        await request(
              '/storage/v1/object/sign/montme-content/$path',
              method: 'POST',
              body: {'expiresIn': 60},
            )
            as Map;
    return '$url/storage/v1${data['signedURL'] ?? data['signedUrl']}';
  }
}
