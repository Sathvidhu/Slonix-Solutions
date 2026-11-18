import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:montme/services/company_cloud.dart';
import 'package:montme/services/app_store.dart';
import 'package:montme/models/entities.dart';

void main() {
  test(
    'Calls to device-created leads sync even without a company contact',
    () async {
      final writes = <Map<String, dynamic>>[];
      final cloud = CompanyCloud(
        persistSession: false,
        client: MockClient((r) async {
          if (r.url.path.endsWith('employee-login')) {
            return http.Response(
              jsonEncode({
                'access_token': 'token',
                'refresh_token': 'refresh',
                'expires_in': 3600,
                'user': {'id': 'user'},
              }),
              200,
            );
          }
          if (r.url.path.endsWith('/employees')) {
            return http.Response(
              jsonEncode([
                {
                  'id': 'employee',
                  'employee_code': 'EMP-1',
                  'name': 'Employee',
                },
              ]),
              200,
            );
          }
          if (r.url.path.endsWith('/call_records') && r.method == 'POST') {
            writes.addAll(
              (jsonDecode(r.body) as List).map(
                (v) => Map<String, dynamic>.from(v),
              ),
            );
            return http.Response('', 201);
          }
          return http.Response('[]', 200);
        }),
      );
      SharedPreferences.setMockInitialValues({});
      final s = AppStore(
        await SharedPreferences.getInstance(),
        companyCloud: cloud,
      );
      await s.connectCompany('EMP-1', 'unused-test');
      s.leads.add(
        Lead(
          id: 'local',
          name: 'Device lead',
          company: 'Institute',
          phone: '9876543210',
        ),
      );
      s.calls.add(
        CallEntry(
          id: 'native-call',
          leadId: 'local',
          at: DateTime.now(),
          seconds: 22,
          source: 'Android',
        ),
      );
      await s.syncCompany();
      expect(cloud.error, isNull);
      expect(writes.single['contact_id'], isNull);
      expect(writes.single['lead_name'], 'Device lead');
      expect(writes.single['duration_seconds'], 22);
      await s.syncCompany();
      expect(writes.length, 1);
    },
  );
}
