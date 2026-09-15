import 'dart:convert';

import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:http/http.dart' as http;

class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient({
    required NextcloudAccount account,
    http.Client? inner,
  })  : _account = account,
        _inner = inner ?? http.Client();

  final NextcloudAccount _account;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_sameOrigin(request.url, _account.serverUrl)) {
      final credentials = base64Encode(
        utf8.encode('${_account.loginName}:${_account.appPassword}'),
      );
      request.headers.putIfAbsent('Authorization', () => 'Basic $credentials');
      request.headers.putIfAbsent(
        'User-Agent',
        () => 'CloudTasks/0.8.0 (Flutter; CalDAV)',
      );
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  static bool _sameOrigin(Uri left, Uri right) {
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        left.port == right.port;
  }
}
