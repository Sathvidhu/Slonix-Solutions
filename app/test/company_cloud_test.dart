import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:montme/services/company_cloud.dart';

void main() {
  test(
    'Missing attendance function explains the company server upgrade',
    () async {
      final cloud = CompanyCloud(
        persistSession: false,
        client: MockClient(
          (_) async => http.Response(
            '{"code":"PGRST202","message":"Function not in schema cache"}',
            404,
          ),
        ),
      );
      await expectLater(
        cloud.request('/rest/v1/rpc/clock_in', method: 'POST', body: {}),
        throwsA(isA<AttendanceUnavailable>()),
      );
    },
  );

  test(
    'Company sign-in requires an enrolled employee, not just a valid token',
    () async {
      final cloud = CompanyCloud(
        persistSession: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/token')) {
            return http.Response(
              jsonEncode({
                'access_token': 'test',
                'refresh_token': 'refresh',
                'expires_in': 3600,
                'user': {'id': 'u'},
              }),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      await expectLater(
        cloud.signIn('not-enrolled@example.com', 'test'),
        throwsStateError,
      );
      expect(cloud.connected, false);
    },
  );
  test(
    'Company work fetch uses employee authorization and private download links',
    () async {
      final calls = <http.Request>[];
      final cloud = CompanyCloud(
        persistSession: false,
        client: MockClient((request) async {
          calls.add(request);
          if (request.url.path.endsWith('/token')) {
            return http.Response(
              jsonEncode({
                'access_token': 'test-token',
                'refresh_token': 'refresh',
                'expires_in': 3600,
                'user': {'id': 'u'},
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/employees')) {
            return http.Response(
              '[{"id":"employee","name":"Asha","email":"asha@example.com","employee_code":"BDA-01"}]',
              200,
            );
          }
          if (request.url.path.endsWith('/assignments')) {
            return http.Response(
              '[{"id":"a","release_at":"2026-11-17T09:00:00Z"},{"id":"b","release_at":"2026-11-18T09:00:00Z"}]',
              200,
            );
          }
          if (request.url.path.contains('/object/sign/')) {
            return http.Response(
              '{"signedURL":"/object/sign/montme-content/file?token=short-lived"}',
              200,
            );
          }
          if (request.url.path.endsWith('/acknowledge_assignment')) {
            return http.Response('', 204);
          }
          return http.Response('[]', 200);
        }),
      );
      await cloud.signIn('asha@example.com', 'test');
      await cloud.fetchWork();
      expect(cloud.connected, true);
      expect(cloud.assignments.first['id'], 'b');
      expect(
        await cloud.signedFile('file'),
        contains('/storage/v1/object/sign/'),
      );
      await cloud.acknowledge('a', 'completed');
      expect(
        calls
            .skip(1)
            .every((r) => r.headers['Authorization'] == 'Bearer test-token'),
        true,
      );
      final ack = jsonDecode(calls.last.body) as Map;
      expect(ack['status_input'], 'completed');
      cloud.disconnect();
      expect(cloud.assignments, isEmpty);
      expect(cloud.connected, false);
    },
  );
}
