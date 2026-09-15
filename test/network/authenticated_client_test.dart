import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:cloud_tasks/src/network/authenticated_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final account = NextcloudAccount(
    id: 'account',
    serverUrl: Uri(
      scheme: 'https',
      host: 'cloud.example',
      path: '/nextcloud',
    ),
    loginName: 'alice',
    appPassword: 'app-password',
  );

  test('adds authorization only to the account origin', () async {
    final authorizationByHost = <String, String?>{};
    final inner = MockClient((request) async {
      authorizationByHost[request.url.host] =
          request.headers['Authorization'];
      return http.Response('ok', 200);
    });
    final client = AuthenticatedClient(account: account, inner: inner);
    addTearDown(client.close);

    await client.get(Uri.parse('https://cloud.example/remote.php/dav'));
    await client.get(Uri.parse('https://elsewhere.example/redirect'));

    expect(authorizationByHost['cloud.example'], startsWith('Basic '));
    expect(authorizationByHost['elsewhere.example'], isNull);
  });
}
