import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'xlsx.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/entities.dart';
import 'call_bridge.dart';
import 'company_cloud.dart';
import 'break_policy.dart';
import 'device_alerts.dart';

class AppStore extends ChangeNotifier {
  AppStore(
    this.prefs, {
    Future<List<Map<String, dynamic>>> Function(DateTime)? callReader,
    CompanyCloud? companyCloud,
  }) : _callReader = callReader ?? CallBridge.read,
       cloud = companyCloud ?? CompanyCloud();
  final SharedPreferences prefs;
  final Future<List<Map<String, dynamic>>> Function(DateTime) _callReader;
  final CompanyCloud cloud;
  bool initializing = false;
  List<Map<String, dynamic>> localAlerts = [];
  BreakPolicy get breakPolicy => BreakPolicy.fromSettings(cloud.settings);
  String? _registeredPush;
  bool cloudBusy = false;
  String? _lastCloudUpload;
  String get _outboxKey => 'montme.cloud.outbox.${cloud.employee?['id']}';
  Map<String, dynamic> get _contactMap => Map<String, dynamic>.from(
    jsonDecode(prefs.getString('montme.cloud.contacts') ?? '{}') as Map,
  );
  Future<void> connectCompany(String email, String password) async {
    await cloud.signIn(email, password);
    await acceptCompanySession();
  }

  Future<void> acceptCompanySession() async {
    final employee = cloud.employee!;
    _lastCloudUpload = null;
    final owner = prefs.getString('montme.cloud.owner');
    if ((owner != null && owner != employee['id']) ||
        (owner == null &&
            (sessions.isNotEmpty || calls.isNotEmpty || leads.isNotEmpty) &&
            employeeId != employee['employee_code'])) {
      await cloud.signOut();
      throw StateError(
        'Local work records belong to a different employee ID. Use the correct account or a fresh app installation after backing up your records.',
      );
    }
    await prefs.setString('montme.cloud.owner', employee['id'] as String);
    name = employee['name'] as String;
    employeeId = employee['employee_code'] as String;
    await save();
    await syncCompany();
    await scheduleAttendanceAlerts();
  }

  Future<void> restoreCompany() async {
    initializing = true;
    notifyListeners();
    try {
      if (await cloud.restoreSession()) {
        await acceptCompanySession();
      }
    } catch (e) {
      cloud.error = e.toString();
    } finally {
      initializing = false;
      notifyListeners();
    }
  }

  Future<void> disconnectCompany() async {
    if (_registeredPush != null && cloud.connected) {
      try {
        await cloud.unregisterPush(_registeredPush!);
      } catch (_) {}
    }
    await cloud.signOut();
    _registeredPush = null;
    await _safeAlert(DeviceAlerts.clear(dismissNotifications: true));
    notifyListeners();
  }

  Future<void> _safeAlert(Future<void> action) async {
    try {
      await action;
    } catch (_) {}
  }

  void addLocalAlert(
    String id,
    String title,
    String body, {
    String kind = 'attendance',
    DateTime? at,
  }) {
    if (localAlerts.any((n) => n['id'] == id)) return;
    localAlerts.insert(0, {
      'id': id,
      'title': title,
      'body': body,
      'kind': kind,
      'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'read_at': null,
      'priority': kind == 'break_reminder' ? 'High' : 'Normal',
    });
    unawaited(_safeAlert(DeviceAlerts.show(id, title, body)));
  }

  Duration breakFor(DateTime day) => sessions.fold(
    Duration.zero,
    (v, s) => v + s.breakBetween(day, day.add(const Duration(days: 1))),
  );
  Duration get currentBreak => active?.onBreak == true
      ? DateTime.now().difference(DateTime.parse(active!.breaks.last['start']!))
      : Duration.zero;
  Future<void> refreshAttendanceAlerts({DateTime? at}) async {
    final now = at ?? DateTime.now();
    var changed = false;
    for (final shift in sessions) {
      for (var i = 0; i < shift.breaks.length; i++) {
        final pause = shift.breaks[i],
            deadline = breakPolicy.savedDeadline(pause),
            end = DateTime.tryParse(pause['end'] ?? '');
        if (!now.isBefore(deadline) && (end == null || end.isAfter(deadline))) {
          final id = 'local-break-reminder:${shift.id}:$i';
          if (!localAlerts.any((n) => n['id'] == id)) {
            addLocalAlert(
              id,
              '${breakPolicy.kind(pause)} break exceeded',
              'Your allowed break time has elapsed. Resume work in Montme.',
              kind: 'break_reminder',
              at: deadline,
            );
            changed = true;
          }
        }
      }
    }
    if (changed) await save();
  }

  Future<void> scheduleAttendanceAlerts() async {
    final shift = active;
    if (shift == null) return;
    if (shift.onBreak) {
      final p = shift.breaks.last, deadline = breakPolicy.savedDeadline(p);
      if (deadline.isAfter(DateTime.now())) {
        await _safeAlert(
          DeviceAlerts.schedule(
            'local-break-reminder:${shift.id}:${shift.breaks.length - 1}',
            '${breakPolicy.kind(p)} break exceeded',
            'Your allowed break time has elapsed. Open Montme to resume work.',
            deadline,
          ),
        );
      }
    }
    for (final kind in ['lunch', 'evening']) {
      final start = breakPolicy.windowStart(kind, DateTime.now());
      if (start.isAfter(DateTime.now())) {
        await _safeAlert(
          DeviceAlerts.schedule(
            'window:$kind:${shift.id}',
            '$kind break window is open',
            kind == 'lunch'
                ? 'Lunch is 1:30 PM to 2:30 PM IST. Record your actual break in Montme.'
                : 'Evening break is 5:00 PM to 5:30 PM IST. Record your actual break in Montme.',
            start,
          ),
        );
      }
    }
    await refreshAttendanceAlerts();
  }

  Future<void> refreshRemoteAlerts() async {
    final eid = cloud.employee!['id'], key = 'montme.notifications.seen.$eid';
    final seen = (prefs.getStringList(key) ?? []).toSet(),
        fresh = <Map<String, dynamic>>[];
    for (final n in cloud.notifications) {
      if (n['cancelled_at'] != null ||
          DateTime.parse(n['available_at'] as String).isAfter(DateTime.now())) {
        continue;
      }
      if (!seen.contains(n['id'])) {
        seen.add(n['id'] as String);
        fresh.add(n);
      }
    }
    final recent = fresh
        .where(
          (n) => DateTime.parse(
            n['available_at'] as String,
          ).isAfter(DateTime.now().subtract(const Duration(days: 1))),
        )
        .toList();
    if (recent.length > 5) {
      await _safeAlert(
        DeviceAlerts.show(
          'work-summary',
          'New work notifications',
          'You have ${recent.length} new notifications. Open Montme to review them.',
        ),
      );
    } else {
      for (final n in recent) {
        final duplicate = localAlerts.any(
          (a) =>
              a['kind'] == n['kind'] &&
              DateTime.parse(a['at'] as String)
                      .difference(DateTime.parse(n['available_at'] as String))
                      .inSeconds
                      .abs() <
                  2,
        );
        if (!duplicate) {
          await _safeAlert(
            DeviceAlerts.show(
              n['id'] as String,
              n['title'] as String,
              n['body'] as String,
            ),
          );
        }
      }
    }
    await prefs.setStringList(
      key,
      seen.toList().reversed.take(5000).toList().reversed.toList(),
    );
    if (DeviceAlerts.supported) {
      try {
        final state = await DeviceAlerts.status();
        String? token = state['token'] as String?;
        if (token == null &&
            cloud.settings['firebase_config'] is Map &&
            (cloud.settings['firebase_config'] as Map).isNotEmpty) {
          token = await DeviceAlerts.configurePush(
            Map<String, dynamic>.from(cloud.settings['firebase_config'] as Map),
          );
        }
        if (token != null && token != _registeredPush) {
          await cloud.registerPush(token);
          _registeredPush = token;
        }
      } catch (e) {
        cloud.error = 'Work synced; push registration needs attention: $e';
      }
    }
  }

  List<Map<String, dynamic>> get notificationInbox {
    final remote = cloud.notifications
        .where(
          (n) =>
              n['cancelled_at'] == null &&
              !DateTime.parse(
                n['available_at'] as String,
              ).isAfter(DateTime.now()),
        )
        .map(
          (n) => <String, dynamic>{
            ...n,
            'at': n['available_at'],
            'remote': true,
            'read_at': cloud.notificationReceipts
                .where(
                  (r) =>
                      r['notification_id'] == n['id'] &&
                      r['user_id'] == cloud.userId,
                )
                .firstOrNull?['read_at'],
          },
        )
        .toList();
    final local = localAlerts.where(
      (a) => !remote.any(
        (n) =>
            n['kind'] == a['kind'] &&
            DateTime.parse(a['at'] as String)
                    .difference(DateTime.parse(n['at'] as String))
                    .inSeconds
                    .abs() <
                2,
      ),
    );
    return [...remote, ...local]..sort(
      (a, b) => DateTime.parse(
        b['at'] as String,
      ).compareTo(DateTime.parse(a['at'] as String)),
    );
  }

  Future<void> setNotificationRead(Map<String, dynamic> n, bool read) async {
    if (n['remote'] == true) {
      await cloud.markNotification(n['id'] as String, read);
      await cloud.fetchWork();
    } else {
      final a = localAlerts.firstWhere((v) => v['id'] == n['id']);
      a['read_at'] = read ? DateTime.now().toUtc().toIso8601String() : null;
    }
    await save();
  }

  Future<void> queueContactUpdate(Lead lead) async {
    if (!cloud.connected) return;
    final remoteId = _contactMap[lead.id];
    if (remoteId == null) return;
    final box = Map<String, dynamic>.from(
      jsonDecode(prefs.getString(_outboxKey) ?? '{}') as Map,
    );
    box[remoteId as String] = {
      'contact_id_input': remoteId,
      'status_input': lead.status,
      'notes_input': lead.notes,
      'follow_up_input': lead.followUp?.toUtc().toIso8601String(),
    };
    await prefs.setString(_outboxKey, jsonEncode(box));
  }

  Future<void> syncCompany() async {
    if (!cloud.connected || cloudBusy) return;
    cloudBusy = true;
    try {
      await cloud.fetchWork();
      final box = Map<String, dynamic>.from(
        jsonDecode(prefs.getString(_outboxKey) ?? '{}') as Map,
      );
      for (final entry in box.entries.toList()) {
        if (!cloud.contacts.any((c) => c['id'] == entry.key)) {
          continue;
        }
        await cloud.request(
          '/rest/v1/rpc/update_my_contact',
          method: 'POST',
          body: entry.value,
        );
        final latest = Map<String, dynamic>.from(
          jsonDecode(prefs.getString(_outboxKey) ?? '{}') as Map,
        );
        if (jsonEncode(latest[entry.key]) == jsonEncode(entry.value)) {
          latest.remove(entry.key);
          await prefs.setString(_outboxKey, jsonEncode(latest));
        }
      }
      await cloud.fetchWork();
      final map = _contactMap;
      for (final remote in cloud.contacts) {
        final old = leads
            .where(
              (l) =>
                  map[l.id] == remote['id'] ||
                  phoneKey(l.phone) == phoneKey(remote['phone'] as String),
            )
            .firstOrNull;
        final localId = old?.id ?? remote['id'] as String;
        map[localId] = remote['id'];
        final value = Lead(
          id: localId,
          name: remote['name'] as String,
          company: (remote['institution'] ?? remote['company'] ?? '') as String,
          phone: remote['phone'] as String,
          status: remote['status'] as String,
          notes: remote['notes'] as String,
          followUp: DateTime.tryParse(
            remote['follow_up_at'] as String? ?? '',
          )?.toLocal(),
        );
        final index = leads.indexWhere((l) => l.id == localId);
        if (index < 0) {
          leads.add(value);
        } else {
          leads[index] = value;
        }
      }
      await prefs.setString('montme.cloud.contacts', jsonEncode(map));
      final eid = cloud.employee!['id'];
      final remoteIds = cloud.contacts.map((c) => c['id']).toSet();
      final uploadSignature = jsonEncode({
        'calls': calls.map((c) => c.toJson()).toList(),
        'sessions': sessions.map((v) => v.toJson()).toList(),
        'contacts': cloud.contacts.map((v) => v['id']).toList(),
        'mapping': map,
      });
      if (_lastCloudUpload != uploadSignature) {
        await cloud.upsert(
          'call_records',
          'employee_id,device_call_id',
          calls
              .map(
                (c) => <String, dynamic>{
                  'employee_id': eid,
                  'contact_id': remoteIds.contains(map[c.leadId])
                      ? map[c.leadId]
                      : null,
                  'lead_name': leadFor(c.leadId)?.name ?? '',
                  'device_call_id': c.id,
                  'phone': leadFor(c.leadId)?.phone ?? '',
                  'started_at': c.at.toUtc().toIso8601String(),
                  'duration_seconds': c.seconds,
                  'direction': c.direction,
                  'source': c.source,
                  'outcome': c.outcome,
                  'notes': c.note,
                },
              )
              .toList(),
        );
        await cloud.upsert(
          'shift_records',
          'employee_id,device_shift_id',
          sessions
              .map(
                (shift) => <String, dynamic>{
                  'employee_id': eid,
                  'device_shift_id': shift.id,
                  'started_at': shift.start.toUtc().toIso8601String(),
                  'ended_at': shift.end?.toUtc().toIso8601String(),
                  'breaks': shift.breaks.map((b) => {for(final entry in b.entries) entry.key: ['start','end','deadline'].contains(entry.key) && entry.value != null ? DateTime.parse(entry.value!).toUtc().toIso8601String() : entry.value}).toList(),
                },
              )
              .toList(),
        );
        _lastCloudUpload = uploadSignature;
      }
      cloud.lastSync = DateTime.now();
      cloud.error = null;
      await refreshRemoteAlerts();
      await save();
    } catch (e) {
      cloud.error = e.toString();
      addLocalAlert(
        'sync-error:${e.toString()}',
        'Work sync needs attention',
        'Some records have not reached your admin. Use Reload to retry. ${e.toString()}',
        kind: 'sync',
      );
      await save();
      notifyListeners();
    } finally {
      cloudBusy = false;
    }
  }

  String name = '', employeeId = '', company = '';
  bool consent = false;
  DateTime? lastImport;
  List<Lead> leads = [];
  List<WorkSession> sessions = [];
  List<CallEntry> calls = [];
  String? error;
  String? pendingLeadId;
  DateTime? pendingDialAt;
  List<DateTime> reportDays(DateTime end) =>
      List.generate(7, (i) => end.subtract(Duration(days: 6 - i)))
          .where(
            (d) =>
                sessions.any(
                  (v) =>
                      v.start.isBefore(d.add(const Duration(days: 1))) &&
                      (v.end ?? DateTime.now()).isAfter(d),
                ) ||
                callsFor(d).isNotEmpty,
          )
          .toList();
  Duration get shiftElapsed =>
      active == null ? Duration.zero : DateTime.now().difference(active!.start);
  bool get canClockOut =>
      active != null &&
      (shiftElapsed >= const Duration(hours: 2) ||
          cloud.exitRequests.any(
            (r) =>
                r['device_shift_id'] == active!.id && r['status'] == 'approved',
          ));
  String? get recordingFolder => prefs.getString('recording.folder');
  bool get hasAdminPassword => prefs.containsKey('admin.hash');
  Future<void> setAdminPassword(String password) async {
    if (hasAdminPassword) {
      throw StateError('Admin password already configured.');
    }
    if (password.length < 8) {
      throw const FormatException('Use at least 8 characters.');
    }
    final salt = List.generate(32, (_) => Random.secure().nextInt(256));
    await prefs.setString('admin.salt', base64Encode(salt));
    await prefs.setString('admin.hash', _passwordHash(password));
  }

  String _passwordHash(String password) {
    List<int> bytes = utf8.encode('${prefs.getString('admin.salt')}:$password');
    for (var i = 0; i < 100000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }

  bool verifyAdmin(String password) =>
      hasAdminPassword &&
      _passwordHash(password) == prefs.getString('admin.hash');
  Future<void> selectRecordingFolder(String password) async {
    if (!hasAdminPassword || !verifyAdmin(password)) {
      throw StateError('Incorrect admin password.');
    }
    final folder = await CallBridge.selectFolder();
    if (folder != null) {
      await prefs.setString('recording.folder', folder);
      notifyListeners();
    }
  }

  List<int> excel() => callsWorkbook(employeeId, name, calls, leadFor);

  Future<void> _writes = Future.value();
  bool get configured => name.isNotEmpty;
  WorkSession? get active => sessions.where((s) => s.end == null).firstOrNull;
  DateTime get today =>
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  List<CallEntry> callsFor(DateTime day) =>
      calls
          .where(
            (c) =>
                !c.at.isBefore(day) &&
                c.at.isBefore(day.add(const Duration(days: 1))),
          )
          .toList()
        ..sort((a, b) => b.at.compareTo(a.at));
  Duration workFor(DateTime day) => sessions.fold(
    Duration.zero,
    (total, s) => total + s.workBetween(day, day.add(const Duration(days: 1))),
  );
  Lead? leadFor(String id) => leads.where((l) => l.id == id).firstOrNull;

  void load() {
    final raw = prefs.getString('montme.v1');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      localAlerts = (j['localAlerts'] as List? ?? [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      pendingLeadId = j['pendingLeadId'];
      pendingDialAt = DateTime.tryParse(j['pendingDialAt'] ?? '');
      name = j['name'];
      employeeId = j['employeeId'];
      company = j['company'];
      consent = j['consent'] ?? false;
      lastImport = j['lastImport'] == null
          ? null
          : DateTime.parse(j['lastImport']);
      leads = (j['leads'] as List).map((x) => Lead.fromJson(x)).toList();
      sessions = (j['sessions'] as List)
          .map((x) => WorkSession.fromJson(x))
          .toList();
      calls = (j['calls'] as List).map((x) => CallEntry.fromJson(x)).toList();
    } catch (_) {
      error =
          'Saved data could not be read. Existing storage has not been overwritten. Restart or restore a backup.';
    }
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'localAlerts': localAlerts,
    'pendingLeadId': pendingLeadId,
    'pendingDialAt': pendingDialAt?.toIso8601String(),
    'name': name,
    'employeeId': employeeId,
    'company': company,
    'consent': consent,
    'lastImport': lastImport?.toIso8601String(),
    'leads': leads.map((e) => e.toJson()).toList(),
    'sessions': sessions.map((e) => e.toJson()).toList(),
    'calls': calls.map((e) => e.toJson()).toList(),
  };
  Future<void> save() async {
    if (error != null) throw StateError(error!);
    final snapshot = jsonEncode(toJson());
    _writes = _writes.catchError((_) {}).then((_) async {
      if (!await prefs.setString('montme.v1', snapshot)) {
        throw StateError('Unable to save on this device.');
      }
    });
    notifyListeners();
    await _writes;
  }

  Future<void> profile(String n, String id, String org) async {
    name = n.trim();
    employeeId = id.trim();
    company = org.trim();
    await save();
  }

  Future<void> clock() async {
    final current = active, now = DateTime.now();
    if (current == null) {
      sessions.add(WorkSession(id: uid(), start: now));
    } else {
      if (shiftElapsed < const Duration(hours: 2) && cloud.connected) {
        await cloud.request(
          '/rest/v1/rpc/consume_early_exit',
          method: 'POST',
          body: {'shift_input': current.id},
        );
      } else if (!canClockOut) {
        throw StateError('Clock out is available after 2 hours from clock in.');
      }
      if (current.onBreak) {
        await refreshAttendanceAlerts();
        current.breaks.last['end'] = now.toIso8601String();
        await _safeAlert(
          DeviceAlerts.cancel(
            'local-break-reminder:${current.id}:${current.breaks.length - 1}',
          ),
        );
      }
      current.end = now;
      await _safeAlert(DeviceAlerts.clear());
    }
    await save();
    await scheduleAttendanceAlerts();
  }

  Future<void> toggleBreak([String? requestedKind]) async {
    final current = active;
    if (current == null) return;
    final now = DateTime.now();
    if (current.onBreak) {
      await refreshAttendanceAlerts();
      current.breaks.last['end'] = now.toIso8601String();
      await _safeAlert(
        DeviceAlerts.cancel(
          'local-break-reminder:${current.id}:${current.breaks.length - 1}',
        ),
      );
      addLocalAlert(
        'local-break-end:${current.id}:${current.breaks.length - 1}',
        'Break recorded',
        'You resumed work. This break is saved in your shift history.',
      );
    } else {
      final kind = requestedKind ?? breakPolicy.kindAt(now),
          reason = breakPolicy.unavailable(kind, now, sessions);
      if (reason != null) throw StateError(reason);
      current.breaks.add({
        'start': now.toIso8601String(),
        'end': null,
        'kind': kind,
        'deadline': breakPolicy.deadline(kind, now).toUtc().toIso8601String(),
      });
      addLocalAlert(
        'local-break-start:${current.id}:${current.breaks.length - 1}',
        '$kind break started',
        'Your break is being recorded. You will be reminded at its limit.',
      );
    }
    await save();
    await scheduleAttendanceAlerts();
  }

  Future<void> upsertLead(Lead lead) async {
    final index = leads.indexWhere((x) => x.id == lead.id);
    if (index < 0) {
      leads.add(lead);
    } else {
      leads[index] = lead;
    }
    await queueContactUpdate(lead);
    await save();
  }

  Future<int> importCalls() async {
    if (!consent) {
      throw const FormatException(
        'Enable business call import in Settings first.',
      );
    }
    if (sessions.isEmpty) {
      throw const FormatException('Clock in before importing business calls.');
    }
    // Re-read the full shift range: handles delayed call-log writes, revocation and late imports.
    final since = sessions
        .map((s) => s.start)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final rows = await _callReader(since);
    if (!consent) return 0;
    var imported = 0;
    for (final row in rows) {
      final id = 'android-${row['id']}-${row['date']}';
      final key = phoneKey(row['number'] as String);
      final lead = leads.where((l) => phoneKey(l.phone) == key).firstOrNull;
      final at = DateTime.fromMillisecondsSinceEpoch(row['date'] as int);
      if (lead == null || !sessions.any((s) => s.contains(at))) continue;
      final index = calls.indexWhere((c) => c.id == id);
      final previous = index < 0 ? null : calls[index];
      final entry = CallEntry(
        id: id,
        leadId: lead.id,
        at: at,
        seconds: row['duration'] as int,
        direction: row['direction'] as String,
        source: 'Android',
        outcome: previous?.outcome ?? 'Not reviewed',
        note: previous?.note ?? '',
      );
      if (index < 0) {
        calls.add(entry);
        imported++;
      } else {
        calls[index] = entry;
      }
    }
    lastImport = DateTime.now();
    await save();
    return imported;
  }

  String csv() {
    String cell(Object? v) => '"${v.toString().replaceAll('"', '""')}"';
    final rows = <List<Object?>>[
      [
        'Employee ID',
        'Employee',
        'Lead',
        'Phone',
        'Time',
        'Direction',
        'Duration seconds',
        'Outcome',
        'Note',
        'Source',
      ],
      ...calls.map(
        (c) => [
          employeeId,
          name,
          leadFor(c.leadId)?.name ?? '',
          leadFor(c.leadId)?.phone ?? '',
          c.at.toIso8601String(),
          c.direction,
          c.seconds,
          c.outcome,
          c.note,
          c.source,
        ],
      ),
    ];
    // Protect spreadsheet consumers against formula injection.
    String safe(Object? v) {
      final s = v?.toString() ?? '';
      return cell(RegExp(r'^[=+@\-\t\r]').hasMatch(s) ? "'$s" : s);
    }

    return rows.map((r) => r.map(safe).join(',')).join('\r\n');
  }

  Future<void> restore(String raw) async {
    await _writes.catchError((_) {});
    await _writes;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['version'] != 1 ||
        j['name'] is! String ||
        (j['name'] as String).trim().isEmpty ||
        j['employeeId'] is! String ||
        j['company'] is! String) {
      throw const FormatException('This is not a Montme v1 backup.');
    }
    final newLeads = (j['leads'] as List).map((x) => Lead.fromJson(x)).toList();
    final newSessions = (j['sessions'] as List)
        .map((x) => WorkSession.fromJson(x))
        .toList();
    final newCalls = (j['calls'] as List)
        .map((x) => CallEntry.fromJson(x))
        .toList();
    if (newLeads.map((l) => l.id).toSet().length != newLeads.length ||
        newLeads.map((l) => phoneKey(l.phone)).toSet().length !=
            newLeads.length ||
        newCalls.map((c) => c.id).toSet().length != newCalls.length ||
        newSessions.map((s) => s.id).toSet().length != newSessions.length ||
        newLeads.any(
          (l) =>
              l.id.isEmpty ||
              l.name.trim().isEmpty ||
              phoneKey(l.phone).length < 7 ||
              ![
                'New',
                'Contacted',
                'Interested',
                'Follow-up',
                'Won',
                'Not interested',
              ].contains(l.status),
        ) ||
        newCalls.any(
          (c) =>
              !newLeads.any((l) => l.id == c.leadId) ||
              !['Manual', 'Android'].contains(c.source) ||
              ![
                'Incoming',
                'Outgoing',
                'Missed',
                'Rejected',
              ].contains(c.direction),
        )) {
      throw const FormatException(
        'Backup contains invalid or duplicate records.',
      );
    }
    for (final session in newSessions) {
      DateTime previousEnd = session.start;
      for (final pause in session.breaks) {
        final start = DateTime.parse(pause['start']!);
        final end = pause['end'] == null ? null : DateTime.parse(pause['end']!);
        if (start.isBefore(previousEnd) ||
            (end != null && end.isBefore(start)) ||
            (session.end != null &&
                (end == null || end.isAfter(session.end!))) ||
            (end == null && pause != session.breaks.last)) {
          throw const FormatException('Backup contains invalid breaks.');
        }
        previousEnd = end ?? DateTime.now();
      }
    }
    if (newSessions.where((s) => s.end == null).length > 1 ||
        newCalls.any((c) => c.seconds < 0) ||
        newSessions.any((s) => s.end != null && s.end!.isBefore(s.start))) {
      throw const FormatException('Backup contains invalid records.');
    }
    if (newLeads.map((l) => l.id).toSet().length != newLeads.length ||
        newCalls.map((c) => c.id).toSet().length != newCalls.length ||
        newSessions.map((s) => s.id).toSet().length != newSessions.length ||
        newCalls.any((c) => !newLeads.any((l) => l.id == c.leadId)) ||
        newLeads.any(
          (l) => l.name.trim().isEmpty || phoneKey(l.phone).length < 7,
        )) {
      throw const FormatException(
        'Backup contains invalid or duplicate records.',
      );
    }
    final saved = jsonEncode({...j, 'consent': false, 'lastImport': null});
    if (!await prefs.setString('montme.v1', saved)) {
      throw StateError('Could not restore backup.');
    }
    leads = newLeads;
    sessions = newSessions;
    calls = newCalls;
    name = j['name'];
    employeeId = j['employeeId'];
    company = j['company'];
    consent = false;
    lastImport = null;
    error = null;
    notifyListeners();
  }
}
