import 'dart:convert';

import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:http/http.dart' as http;

typedef BrowserLauncher = Future<bool> Function(Uri url);
typedef PollDelay = Future<void> Function(Duration duration);

class LoginFlowV2 {
  LoginFlowV2({
    required http.Client client,
    required BrowserLauncher openBrowser,
    PollDelay? delay,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPollAttempts = 600,
  }) : _client = client,
       _openBrowser = openBrowser,
       _delay = delay ?? Future<void>.delayed;

  final http.Client _client;
  final BrowserLauncher _openBrowser;
  final PollDelay _delay;
  final Duration pollInterval;
  final int maxPollAttempts;

  Future<NextcloudAccount> authenticate(String serverInput) async {
    final serverUrl = normalizeServerUrl(serverInput);
    final startUrl = appendPath(serverUrl, 'index.php/login/v2');
    final startResponse = await _client.post(
      startUrl,
      headers: const <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'CloudTasks/0.8.0 (Flutter; Nextcloud Login Flow v2)',
      },
    );
    if (startResponse.statusCode != 200) {
      throw LoginFlowException(
        'Nextcloud rejected the login request.',
        statusCode: startResponse.statusCode,
      );
    }

    final start = _decodeObject(startResponse.body, 'login response');
    final loginValue = start['login'];
    final pollValue = start['poll'];
    if (loginValue is! String || pollValue is! Map<Object?, Object?>) {
      throw const LoginFlowException(
        'Nextcloud returned an incomplete login response.',
      );
    }

    final token = pollValue['token'];
    final endpointValue = pollValue['endpoint'];
    if (token is! String || endpointValue is! String) {
      throw const LoginFlowException(
        'Nextcloud returned incomplete polling information.',
      );
    }

    final loginUrl = _httpsEndpoint(loginValue, 'login');
    final launched = await _openBrowser(loginUrl);
    if (!launched) {
      throw const LoginFlowException(
        'The system browser could not open the Nextcloud login page.',
      );
    }

    final endpoint = _httpsEndpoint(endpointValue, 'polling');
    for (var attempt = 0; attempt < maxPollAttempts; attempt++) {
      if (attempt > 0) {
        await _delay(pollInterval);
      }

      http.Response pollResponse;
      try {
        pollResponse = await _client.post(
          endpoint,
          headers: const <String, String>{
            'Accept': 'application/json',
            'User-Agent': 'CloudTasks/0.8.0 (Flutter)',
          },
          body: <String, String>{'token': token},
        );
      } on http.ClientException {
        continue;
      }
      if (pollResponse.statusCode == 404) {
        continue;
      }
      if (pollResponse.statusCode != 200) {
        throw LoginFlowException(
          'Nextcloud could not complete authentication.',
          statusCode: pollResponse.statusCode,
        );
      }

      final completed = _decodeObject(pollResponse.body, 'poll response');
      final completedServer = completed['server'];
      final loginName = completed['loginName'];
      final appPassword = completed['appPassword'];
      if (completedServer is! String ||
          loginName is! String ||
          appPassword is! String) {
        throw const LoginFlowException(
          'Nextcloud returned incomplete account credentials.',
        );
      }

      final canonicalServer = normalizeServerUrl(completedServer);
      return NextcloudAccount(
        id: NextcloudAccount.createId(canonicalServer, loginName),
        serverUrl: canonicalServer,
        loginName: loginName,
        appPassword: appPassword,
      );
    }

    throw const LoginFlowException(
      'Nextcloud login timed out before authorization was completed.',
    );
  }

  static Uri normalizeServerUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      throw const LoginFlowException('Enter your Nextcloud server address.');
    }
    if (!value.contains('://')) {
      value = 'https://$value';
    }

    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.host.isEmpty || parsed.userInfo.isNotEmpty) {
      throw const LoginFlowException('Enter a valid Nextcloud server address.');
    }
    if (parsed.scheme.toLowerCase() != 'https') {
      throw const LoginFlowException(
        'Cloud Tasks requires HTTPS to protect your app password.',
      );
    }

    final normalizedPath = parsed.path.replaceAll(RegExp(r'/+$'), '');
    return parsed.replace(
      scheme: parsed.scheme.toLowerCase(),
      path: normalizedPath,
      query: null,
      fragment: null,
    );
  }

  static Uri appendPath(Uri base, String relativePath) {
    final basePath = base.path.replaceAll(RegExp(r'/+$'), '');
    final relative = relativePath.replaceAll(RegExp(r'^/+'), '');
    return base.replace(
      path: '$basePath/$relative',
      query: null,
      fragment: null,
    );
  }

  static Uri _httpsEndpoint(String value, String label) {
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        parsed.scheme.toLowerCase() != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty) {
      throw LoginFlowException('Nextcloud returned an invalid $label address.');
    }
    return parsed;
  }

  static Map<String, Object?> _decodeObject(String body, String label) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<Object?, Object?>) {
        final result = <String, Object?>{};
        for (final entry in decoded.entries) {
          final key = entry.key;
          if (key is! String) {
            throw const FormatException('JSON object key is not a string.');
          }
          result[key] = entry.value;
        }
        return result;
      }
    } on FormatException {
      // The caller receives a stable, credential-free error below.
    }
    throw LoginFlowException('Nextcloud returned an invalid $label.');
  }
}

class LoginFlowException implements Exception {
  const LoginFlowException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
