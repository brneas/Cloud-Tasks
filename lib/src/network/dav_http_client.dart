import 'dart:async';

import 'package:http/http.dart' as http;

typedef DavRetryDelay = Future<void> Function(Duration duration);

class DavHttpClient {
  DavHttpClient(
    this._client, {
    DavRetryDelay? delay,
    this.maxNetworkAttempts = 3,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _delay = delay ?? Future<void>.delayed;

  final http.Client _client;
  final DavRetryDelay _delay;
  final int maxNetworkAttempts;
  final Duration requestTimeout;

  Future<http.Response> request(
    String method,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    String? body,
    int maxRedirects = 5,
  }) async {
    var currentUrl = url;
    var currentMethod = method;
    var remainingRedirects = maxRedirects;

    while (true) {
      final response = await _sendWithRetry(
        currentMethod,
        currentUrl,
        headers: headers,
        body: body,
      );
      if (!_isRedirect(response.statusCode)) {
        return response;
      }
      if (remainingRedirects-- <= 0) {
        throw DavHttpException(
          method: currentMethod,
          url: currentUrl,
          statusCode: response.statusCode,
          message: 'Too many redirects.',
        );
      }

      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        throw DavHttpException(
          method: currentMethod,
          url: currentUrl,
          statusCode: response.statusCode,
          message: 'Redirect response did not include a Location header.',
        );
      }

      currentUrl = currentUrl.resolve(location);
      if (response.statusCode == 303) {
        currentMethod = 'GET';
      }
    }
  }

  Future<http.Response> _sendWithRetry(
    String method,
    Uri url, {
    required Map<String, String> headers,
    required String? body,
  }) async {
    Object? lastError;
    final configuredAttempts = maxNetworkAttempts < 1 ? 1 : maxNetworkAttempts;
    final attempts = _isReadRequest(method) ? configuredAttempts : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        await _delay(Duration(milliseconds: 300 * attempt));
      }

      final request = http.Request(method, url)
        ..followRedirects = false
        ..headers.addAll(headers);
      if (body != null && method != 'GET') {
        request.body = body;
      }

      try {
        final streamed = await _client.send(request).timeout(requestTimeout);
        return await http.Response.fromStream(streamed).timeout(requestTimeout);
      } on http.ClientException catch (error) {
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      }
    }

    throw DavHttpException(
      method: method,
      url: url,
      message: 'The network connection to Nextcloud was interrupted.',
      cause: lastError,
    );
  }

  static bool _isRedirect(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  static bool _isReadRequest(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
      case 'HEAD':
      case 'OPTIONS':
      case 'PROPFIND':
      case 'REPORT':
        return true;
      default:
        return false;
    }
  }
}

class DavHttpException implements Exception {
  const DavHttpException({
    required this.method,
    required this.url,
    required this.message,
    this.statusCode,
    this.responseBody,
    this.cause,
  });

  final String method;
  final Uri url;
  final int? statusCode;
  final String message;
  final String? responseBody;
  final Object? cause;

  @override
  String toString() => message;
}
