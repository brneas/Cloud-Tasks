import 'dart:convert';

import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/caldav/dav_xml.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:xml/xml.dart';

enum CalendarShareKind { user, group }

class CalendarShare {
  const CalendarShare({
    required this.principalHref,
    required this.displayName,
    required this.kind,
    required this.canWrite,
  });

  final String principalHref;
  final String displayName;
  final CalendarShareKind kind;
  final bool canWrite;
}

class CalDavCalendarSharingService {
  const CalDavCalendarSharingService(this._http);

  final DavHttpClient _http;

  Future<List<CalendarShare>> readShares(TaskCalendar calendar) async {
    final response = await _http.request(
      'PROPFIND',
      calendar.href,
      headers: const <String, String>{
        'Accept': 'application/xml, text/xml',
        'Content-Type': 'application/xml; charset=utf-8',
        'Depth': '0',
      },
      body: _inviteRequest,
    );
    if (response.statusCode != 207) {
      throw CalendarSharingException(
        'Could not load list sharing (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    try {
      final document = XmlDocument.parse(response.body);
      final shares = <CalendarShare>[];
      for (final davResponse in document.findAllElements(
        'response',
        namespace: davNamespace,
      )) {
        final properties = successfulDavProperties(davResponse);
        final invite = properties?.getElement(
          'invite',
          namespace: ownCloudNamespace,
        );
        if (invite == null) {
          continue;
        }
        for (final user in invite.findElements(
          'user',
          namespace: ownCloudNamespace,
        )) {
          final href = user
              .getElement('href', namespace: davNamespace)
              ?.innerText
              .trim();
          if (href == null || href.isEmpty) {
            continue;
          }
          final commonName = elementText(
            user,
            'common-name',
            namespace: ownCloudNamespace,
          );
          final kind = href.startsWith('principal:principals/groups/')
              ? CalendarShareKind.group
              : CalendarShareKind.user;
          shares.add(
            CalendarShare(
              principalHref: href,
              displayName: commonName ?? _principalId(href),
              kind: kind,
              canWrite: user
                  .findAllElements('read-write', namespace: ownCloudNamespace)
                  .isNotEmpty,
            ),
          );
        }
      }
      shares.sort(
        (left, right) => left.displayName.toLowerCase().compareTo(
          right.displayName.toLowerCase(),
        ),
      );
      return List<CalendarShare>.unmodifiable(shares);
    } on XmlParserException {
      throw const CalendarSharingException(
        'Nextcloud returned invalid list-sharing data.',
      );
    }
  }

  Future<void> share({
    required TaskCalendar calendar,
    required String recipientId,
    required CalendarShareKind kind,
    required bool canWrite,
  }) async {
    final normalizedId = recipientId.trim();
    if (normalizedId.isEmpty || normalizedId.contains('/')) {
      throw const CalendarSharingException(
        'Enter a valid Nextcloud username or group ID.',
      );
    }
    final type = kind == CalendarShareKind.group ? 'groups' : 'users';
    final principal = 'principal:principals/$type/$normalizedId';
    await _postShare(
      calendar,
      '<oc:set><d:href>${_xml(principal)}</d:href>'
      '${canWrite ? '<oc:read-write/>' : ''}</oc:set>',
      action: 'share the task list',
    );
  }

  Future<void> updatePermission({
    required TaskCalendar calendar,
    required CalendarShare share,
    required bool canWrite,
  }) {
    return _postShare(
      calendar,
      '<oc:set><d:href>${_xml(share.principalHref)}</d:href>'
      '${canWrite ? '<oc:read-write/>' : ''}</oc:set>',
      action: 'change sharing permission',
    );
  }

  Future<void> unshare({
    required TaskCalendar calendar,
    required CalendarShare share,
  }) {
    return _postShare(
      calendar,
      '<oc:remove><d:href>${_xml(share.principalHref)}</d:href></oc:remove>',
      action: 'remove the share',
    );
  }

  Future<void> _postShare(
    TaskCalendar calendar,
    String operation, {
    required String action,
  }) async {
    final response = await _http.request(
      'POST',
      calendar.href,
      headers: const <String, String>{
        'Accept': 'application/xml, text/xml',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body:
          '<?xml version="1.0" encoding="utf-8"?>'
          '<oc:share xmlns:oc="$ownCloudNamespace" xmlns:d="$davNamespace">'
          '$operation</oc:share>',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CalendarSharingException(
        'Nextcloud could not $action (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  static String _principalId(String href) {
    final encoded = href.split('/').last;
    return Uri.decodeComponent(encoded);
  }

  static String _xml(String value) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(value);

  static const _inviteRequest = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
  <d:prop><oc:invite /></d:prop>
</d:propfind>''';
}

class CalendarSharingException implements Exception {
  const CalendarSharingException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
