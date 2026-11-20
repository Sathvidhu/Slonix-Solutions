import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:montme/main.dart';
import 'package:montme/models/entities.dart';
import 'package:montme/services/app_store.dart';
import 'package:montme/services/company_cloud.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<AppStore> store() async {
    SharedPreferences.setMockInitialValues({});
    return AppStore(await SharedPreferences.getInstance());
  }

  test(
    'Excel export is a real workbook with text phone numbers and no formulas',
    () async {
      final s = await store();
      s.name = '=SUM(A1)';
      s.leads.add(
        Lead(id: 'l', name: 'Customer', company: '', phone: '00123456789'),
      );
      s.calls.add(
        CallEntry(
          id: 'c',
          leadId: 'l',
          at: DateTime(2026, 11, 17, 14, 30),
          seconds: 86,
        ),
      );
      final zip = ZipDecoder().decodeBytes(s.excel());
      final sheet = utf8.decode(
        zip.findFile('xl/worksheets/sheet1.xml')!.content,
      );
      expect(sheet, contains('00123456789'));
      expect(sheet, contains('=SUM(A1)'));
      expect(sheet, isNot(contains('<f>')));
      expect(sheet, contains('<v>86</v>'));
    },
  );
  test('Reports include recorded days only', () async {
    final s = await store();
    final today = s.today;
    expect(s.reportDays(today), isEmpty);
    s.sessions.add(
      WorkSession(
        id: 's',
        start: today.add(const Duration(hours: 1)),
        end: today.add(const Duration(hours: 3)),
      ),
    );
    expect(s.reportDays(today), [today]);
  });
  test('Admin password persists and cannot be replaced', () async {
    final s = await store();
    await s.setAdminPassword('company-admin');
    expect(s.verifyAdmin('wrong'), false);
    expect(s.verifyAdmin('company-admin'), true);
    final loaded = AppStore(s.prefs)..load();
    expect(loaded.verifyAdmin('company-admin'), true);
    await expectLater(s.setAdminPassword('replacement'), throwsStateError);
  });
  test(
    'overnight shifts allocate time to each day and subtract overlapping breaks',
    () {
      final shift = WorkSession(
        id: 's',
        start: DateTime(2026, 11, 16, 23),
        end: DateTime(2026, 11, 17, 2),
        breaks: [
          {
            'start': DateTime(2026, 11, 16, 23, 45).toIso8601String(),
            'end': DateTime(2026, 11, 17, 0, 15).toIso8601String(),
          },
        ],
      );
      expect(
        shift
            .workBetween(DateTime(2026, 11, 16), DateTime(2026, 11, 17))
            .inMinutes,
        45,
      );
      expect(
        shift
            .workBetween(DateTime(2026, 11, 17), DateTime(2026, 11, 18))
            .inMinutes,
        105,
      );
    },
  );
  test('profile, leads and active breaks survive a reload', () async {
    final s = await store();
    await s.profile('Asha', 'BDA-01', 'Acme');
    await s.upsertLead(
      Lead(
        id: 'lead',
        name: 'Customer',
        company: 'Example',
        phone: '+919876543210',
      ),
    );
    await s.clock();
    await s.toggleBreak();
    final reloaded = AppStore(s.prefs)..load();
    expect(reloaded.name, 'Asha');
    expect(reloaded.leads.single.name, 'Customer');
    expect(reloaded.active!.onBreak, isTrue);
    await expectLater(reloaded.clock(), throwsStateError);
    expect(reloaded.active, isNotNull);
    reloaded.sessions.clear();
    reloaded.sessions.add(
      WorkSession(
        id: 'old',
        start: DateTime.now().subtract(const Duration(hours: 2, minutes: 1)),
      ),
    );
    await reloaded.toggleBreak();
    await reloaded.clock();
    expect(reloaded.active, isNull);
    expect(reloaded.sessions.single.breaks.single['end'], isNotNull);
  });
  test('CSV escapes quotes and neutralizes spreadsheet formulas', () async {
    final s = await store();
    s.name = '=HYPERLINK("x")';
    s.leads.add(
      Lead(id: 'l', name: 'A, B', company: '', phone: '+919876543210'),
    );
    s.calls.add(
      CallEntry(id: 'c', leadId: 'l', at: DateTime(2026), seconds: 30),
    );
    expect(s.csv(), contains('"\'=HYPERLINK(""x"")"'));
    expect(s.csv(), contains('"A, B"'));
  });
  test('invalid backup is atomic and valid backup resets consent', () async {
    final s = await store();
    await s.profile('Asha', '1', 'Acme');
    final backup = s.toJson();
    backup['consent'] = true;
    await expectLater(s.restore('{"version":1}'), throwsFormatException);
    expect(s.name, 'Asha');
    await s.restore(jsonEncode(backup));
    expect(s.consent, isFalse);
  });
  testWidgets('employee can navigate and clock in from a narrow screen', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final cloud = _AttendanceCloud();
    final s = AppStore(
      await SharedPreferences.getInstance(),
      companyCloud: cloud,
    );
    await s.profile('Asha', '1', 'Acme');
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Workspace(store: s),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Clock in'), findsOneWidget);
    await tester.tap(find.text('Clock in'));
    await tester.pump();
    expect(s.active, isNotNull);
    expect(find.text('Clock out after 2 hours'), findsOneWidget);
    expect(find.text('Submit report and clock out'), findsNothing);
    cloud.employee!['clock_out_time'] = '00:00:00';
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(s.attendanceBusy, isFalse);
    final clockOut = find.text('Clock out');
    await tester.ensureVisible(clockOut);
    await tester.tap(clockOut);
    await tester.pumpAndSettle();
    expect(find.text('Daily Work Report'), findsOneWidget);
    await tester.tap(find.text('Submit report and clock out'));
    await tester.pumpAndSettle();
    expect(s.active, isNull);
    expect(cloud.submittedShift, 'shared-shift');
    await tester.tap(find.text('Leads'));
    await tester.pumpAndSettle();
    expect(find.text('Add lead'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'Android import excludes personal and off-shift calls, deduplicates and refreshes durations',
    () async {
      SharedPreferences.setMockInitialValues({});
      final at = DateTime.now().subtract(const Duration(minutes: 30));
      var seconds = 0;
      final s = AppStore(
        await SharedPreferences.getInstance(),
        callReader: (_) async => [
          {
            'id': '1',
            'number': '+919876543210',
            'date': at.millisecondsSinceEpoch,
            'duration': seconds,
            'direction': 'Outgoing',
          },
          {
            'id': '2',
            'number': '9999999999',
            'date': at.millisecondsSinceEpoch,
            'duration': 200,
            'direction': 'Incoming',
          },
          {
            'id': '3',
            'number': '9876543210',
            'date': at.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
            'duration': 300,
            'direction': 'Outgoing',
          },
        ],
      );
      s.consent = true;
      s.leads.add(
        Lead(id: 'l', name: 'Business', company: 'Acme', phone: '9876543210'),
      );
      s.sessions.add(
        WorkSession(id: 's', start: at.subtract(const Duration(hours: 1))),
      );
      expect(await s.importCalls(), 1);
      expect(s.calls.single.seconds, 0);
      s.calls.single.outcome = 'Interested';
      seconds = 95;
      expect(await s.importCalls(), 0);
      expect(s.calls.single.seconds, 95);
      expect(s.calls.single.outcome, 'Interested');
      expect(s.calls.single.source, 'Android');
    },
  );
  test('revoking consent during an import prevents persistence', () async {
    SharedPreferences.setMockInitialValues({});
    late AppStore s;
    s = AppStore(
      await SharedPreferences.getInstance(),
      callReader: (_) async {
        s.consent = false;
        return [];
      },
    );
    s.consent = true;
    s.sessions.add(WorkSession(id: 's', start: DateTime.now()));
    expect(await s.importCalls(), 0);
    expect(s.lastImport, isNull);
  });
  testWidgets('lead creation and manual call outcome work end to end', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await store();
    await s.profile('Asha', '1', 'Acme');
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Workspace(store: s),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add lead'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Test customer',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone number'),
      '9876543210',
    );
    await tester.tap(find.text('Save lead'));
    await tester.pumpAndSettle();
    expect(s.leads.single.name, 'Test customer');
    await tester.tap(find.text('Calls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log a call'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Talk time in seconds'),
      '120',
    );
    await tester.tap(find.text('Save outcome'));
    await tester.pumpAndSettle();
    expect(s.calls.single.seconds, 120);
    expect(s.calls.single.source, 'Manual');
    expect(s.leads.single.status, 'Follow-up');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _AttendanceCloud extends CompanyCloud {
  _AttendanceCloud() : super(persistSession: false) {
    employee = {'id': 'employee', 'name': 'Asha', 'employee_code': '1'};
  }

  String? submittedShift;

  @override
  bool get connected => true;

  @override
  Future<void> fetchWork() async {}

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    String? prefer,
    bool refresh = true,
  }) async {
    if (path.endsWith('/clock_in')) {
      final shift = <String, dynamic>{
        'device_shift_id': 'shared-shift',
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'ended_at': null,
        'breaks': [],
      };
      shifts = [shift];
      return shift;
    }
    if (path.endsWith('/submit_daily_report')) {
      submittedShift = (body as Map)['shift_input'] as String;
      final shift = {
        ...shifts.single,
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      };
      shifts = [shift];
      return shift;
    }
    throw StateError('Unexpected request: $path');
  }
}
