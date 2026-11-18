import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:montme/main.dart';
import 'package:montme/models/entities.dart';
import 'package:montme/services/app_store.dart';
import 'package:montme/services/break_policy.dart';

void main() {
  const policy = BreakPolicy();
  test(
    'Lunch and evening use fixed IST window ends, not duration from late starts',
    () {
      final lunch = DateTime.utc(2026, 11, 18, 8, 10),
          evening = DateTime.utc(2026, 11, 18, 11, 40);
      expect(policy.unavailable('lunch', lunch, []), isNull);
      expect(policy.deadline('lunch', lunch), DateTime.utc(2026, 11, 18, 9));
      expect(
        policy.unavailable('lunch', DateTime.utc(2026, 11, 18, 9), []),
        isNotNull,
      );
      expect(
        policy.deadline('evening', evening),
        DateTime.utc(2026, 11, 18, 12),
      );
      expect(policy.unavailable('evening', lunch, []), isNotNull);
    },
  );
  test(
    'Extra break allowance is once per IST calendar day across multiple shifts',
    () {
      final first = DateTime.utc(2026, 11, 17, 20);
      final shifts = [
        WorkSession(
          id: 'one',
          start: first,
          breaks: [
            {
              'start': first.toIso8601String(),
              'end': first.add(const Duration(minutes: 5)).toIso8601String(),
              'kind': 'extra',
            },
          ],
        ),
      ];
      expect(
        policy.unavailable('extra', DateTime.utc(2026, 11, 18, 6), shifts),
        isNotNull,
      );
      expect(
        policy.unavailable('extra', DateTime.utc(2026, 11, 18, 20), shifts),
        isNull,
      );
      expect(
        policy.deadline('extra', first),
        first.add(const Duration(minutes: 10)),
      );
    },
  );
  test('Overnight break history retains separate day totals', () {
    final s = WorkSession(
      id: 's',
      start: DateTime(2026, 11, 17, 23),
      end: DateTime(2026, 11, 18, 2),
      breaks: [
        {
          'start': DateTime(2026, 11, 17, 23, 45).toIso8601String(),
          'end': DateTime(2026, 11, 18, 0, 15).toIso8601String(),
        },
      ],
    );
    expect(
      s.breakBetween(DateTime(2026, 11, 17), DateTime(2026, 11, 18)).inMinutes,
      15,
    );
    expect(
      s.breakBetween(DateTime(2026, 11, 18), DateTime(2026, 11, 19)).inMinutes,
      15,
    );
  });
  test(
    'Break overrun alert is persisted once and can be marked read or unread',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppStore(await SharedPreferences.getInstance());
      final start = DateTime.utc(2026, 11, 18, 6),
          deadline = start.add(const Duration(minutes: 10));
      s.sessions.add(
        WorkSession(
          id: 's',
          start: start.subtract(const Duration(hours: 1)),
          breaks: [
            {
              'start': start.toIso8601String(),
              'end': null,
              'kind': 'extra',
              'deadline': deadline.toIso8601String(),
            },
          ],
        ),
      );
      await s.refreshAttendanceAlerts(
        at: deadline.add(const Duration(seconds: 1)),
      );
      await s.refreshAttendanceAlerts(
        at: deadline.add(const Duration(minutes: 1)),
      );
      expect(s.localAlerts.length, 1);
      final loaded = AppStore(s.prefs)..load();
      expect(loaded.localAlerts.length, 1);
      expect(loaded.active!.breaks.last['kind'], 'extra');
      await loaded.setNotificationRead(loaded.notificationInbox.first, true);
      expect(loaded.notificationInbox.first['read_at'], isNotNull);
      await loaded.setNotificationRead(loaded.notificationInbox.first, false);
      expect(loaded.notificationInbox.first['read_at'], isNull);
    },
  );
  testWidgets('Existing local data does not bypass employee authentication', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(await SharedPreferences.getInstance());
    await s.profile('Local name', 'EMP01', 'Montme');
    await tester.pumpWidget(MontmeApp(store: s));
    await tester.pumpAndSettle();
    expect(find.text('Employee ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Clock in'), findsNothing);
  });
}
