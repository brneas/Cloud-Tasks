import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('retries an interrupted read request with a fresh body', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      expect(request.method, 'PROPFIND');
      expect(request.body, '<propfind/>');
      if (requestCount == 1) {
        throw http.ClientException('Connection interrupted');
      }
      return http.Response('<multistatus/>', 207);
    });
    final dav = DavHttpClient(client, delay: (_) async {});

    final response = await dav.request(
      'PROPFIND',
      Uri.parse('https://cloud.example/.well-known/caldav'),
      body: '<propfind/>',
    );

    expect(response.statusCode, 207);
    expect(requestCount, 2);
  });

  test('does not blindly retry an interrupted write request', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      throw http.ClientException('Connection interrupted');
    });
    final dav = DavHttpClient(client, delay: (_) async {});

    await expectLater(
      dav.request(
        'PUT',
        Uri.parse('https://cloud.example/task.ics'),
        body: 'task',
      ),
      throwsA(isA<DavHttpException>()),
    );
    expect(requestCount, 1);
  });
}
