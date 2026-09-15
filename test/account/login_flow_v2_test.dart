import 'dart:convert';

import 'package:cloud_tasks/src/account/login_flow_v2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('LoginFlowV2', () {
    test('opens Nextcloud login and polls for an app password', () async {
      var pollCount = 0;
      Uri? launchedUrl;
      final client = MockClient((request) async {
        if (request.url.path == '/nextcloud/index.php/login/v2') {
          return http.Response(
            jsonEncode(<String, Object?>{
              'login': 'https://cloud.example/login/flow/abc',
              'poll': <String, Object?>{
                'token': 'poll-token',
                'endpoint': 'https://cloud.example/login/v2/poll',
              },
            }),
            200,
          );
        }

        expect(request.url.path, '/login/v2/poll');
        expect(request.bodyFields['token'], 'poll-token');
        pollCount++;
        if (pollCount == 1) {
          return http.Response('', 404);
        }
        return http.Response(
          jsonEncode(<String, String>{
            'server': 'https://cloud.example/nextcloud/',
            'loginName': 'alice',
            'appPassword': 'app-password',
          }),
          200,
        );
      });

      final flow = LoginFlowV2(
        client: client,
        openBrowser: (url) async {
          launchedUrl = url;
          return true;
        },
        delay: (_) async {},
        pollInterval: Duration.zero,
      );
      final account = await flow.authenticate('cloud.example/nextcloud/');

      expect(launchedUrl, Uri.parse('https://cloud.example/login/flow/abc'));
      expect(pollCount, 2);
      expect(account.serverUrl, Uri.parse('https://cloud.example/nextcloud'));
      expect(account.loginName, 'alice');
      expect(account.appPassword, 'app-password');
    });

    test('rejects unencrypted server addresses', () {
      expect(
        () => LoginFlowV2.normalizeServerUrl('http://cloud.example'),
        throwsA(isA<LoginFlowException>()),
      );
    });

    test('keeps polling after a transient background network failure', () async {
      var pollCount = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/index.php/login/v2')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'login': 'https://cloud.example/login/flow/abc',
              'poll': <String, Object?>{
                'token': 'poll-token',
                'endpoint': 'https://cloud.example/login/v2/poll',
              },
            }),
            200,
          );
        }

        pollCount++;
        if (pollCount == 1) {
          throw http.ClientException('Application moved to background');
        }
        return http.Response(
          jsonEncode(<String, String>{
            'server': 'https://cloud.example',
            'loginName': 'alice',
            'appPassword': 'app-password',
          }),
          200,
        );
      });
      final flow = LoginFlowV2(
        client: client,
        openBrowser: (_) async => true,
        delay: (_) async {},
        pollInterval: Duration.zero,
        maxPollAttempts: 2,
      );

      final account = await flow.authenticate('https://cloud.example');

      expect(account.loginName, 'alice');
      expect(pollCount, 2);
    });
  });
}
