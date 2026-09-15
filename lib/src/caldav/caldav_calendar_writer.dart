import 'dart:convert';

import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:xml/xml.dart';

class CalDavCalendarWriter {
  const CalDavCalendarWriter(this._http);

  final DavHttpClient _http;

  Future<TaskCalendar> create({
    required String accountId,
    required Uri calendarHomeUrl,
    required String collectionId,
    required String displayName,
    required String color,
    required int sortOrder,
  }) async {
    final href = _collectionHref(calendarHomeUrl, collectionId);
    final response = await _http.request(
      'MKCALENDAR',
      href,
      headers: const <String, String>{
        'Accept': 'application/xml, text/xml',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: _createBody(displayName, color, sortOrder),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw CalDavCalendarWriteException(
        'Nextcloud rejected the new task list '
        '(HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return TaskCalendar(
      id: href.toString(),
      accountId: accountId,
      href: href,
      displayName: displayName,
      color: color,
      sortOrder: sortOrder,
      isReadOnly: false,
    );
  }

  Future<void> update(
    TaskCalendar calendar, {
    required String displayName,
    required String color,
    required int sortOrder,
  }) async {
    final response = await _http.request(
      'PROPPATCH',
      calendar.href,
      headers: const <String, String>{
        'Accept': 'application/xml, text/xml',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: _updateBody(displayName, color, sortOrder),
    );
    if (response.statusCode != 200 && response.statusCode != 207) {
      throw CalDavCalendarWriteException(
        'Nextcloud rejected the task-list update '
        '(HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 207) {
      _requireSuccessfulPropstats(response.body);
    }
  }

  Future<void> delete(TaskCalendar calendar) async {
    final response = await _http.request(
      'DELETE',
      calendar.href,
      headers: const <String, String>{'Accept': 'application/xml, text/xml'},
    );
    if (response.statusCode == 404) {
      return;
    }
    if (response.statusCode != 200 &&
        response.statusCode != 202 &&
        response.statusCode != 204) {
      throw CalDavCalendarWriteException(
        'Nextcloud rejected the task-list deletion '
        '(HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  static Uri _collectionHref(Uri home, String collectionId) {
    final safeId = collectionId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (safeId.isEmpty) {
      throw const CalDavCalendarWriteException(
        'Could not create a safe task-list address.',
      );
    }
    final path = home.path.endsWith('/') ? home.path : '${home.path}/';
    return home.replace(
      path: '$path${Uri.encodeComponent(safeId)}/',
      query: null,
      fragment: null,
    );
  }

  static String _createBody(String name, String color, int order) {
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<c:mkcalendar xmlns:d="DAV:" '
        'xmlns:c="urn:ietf:params:xml:ns:caldav" '
        'xmlns:a="http://apple.com/ns/ical/">'
        '<d:set><d:prop>'
        '${_properties(name, color, order)}'
        '<c:supported-calendar-component-set>'
        '<c:comp name="VTODO"/>'
        '</c:supported-calendar-component-set>'
        '</d:prop></d:set>'
        '</c:mkcalendar>';
  }

  static String _updateBody(String name, String color, int order) {
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propertyupdate xmlns:d="DAV:" '
        'xmlns:a="http://apple.com/ns/ical/">'
        '<d:set><d:prop>'
        '${_properties(name, color, order)}'
        '</d:prop></d:set>'
        '</d:propertyupdate>';
  }

  static String _properties(String name, String color, int order) {
    final safeName = const HtmlEscape(HtmlEscapeMode.element).convert(name);
    return '<d:displayname>$safeName</d:displayname>'
        '<a:calendar-color>${_normalizedColor(color)}</a:calendar-color>'
        '<a:calendar-order>$order</a:calendar-order>';
  }

  static String _normalizedColor(String source) {
    final value = source.trim().toUpperCase();
    if (RegExp(r'^#[0-9A-F]{6}([0-9A-F]{2})?$').hasMatch(value)) {
      return value.length == 7 ? '${value}FF' : value;
    }
    return '#0082C9FF';
  }

  static void _requireSuccessfulPropstats(String source) {
    try {
      final document = XmlDocument.parse(source);
      for (final propstat in document.findAllElements(
        'propstat',
        namespace: 'DAV:',
      )) {
        final statuses = propstat.findElements('status', namespace: 'DAV:');
        final status = statuses.isEmpty ? null : statuses.first.innerText;
        if (status != null && !status.contains(RegExp(r'\s2\d\d\s'))) {
          throw const CalDavCalendarWriteException(
            'Nextcloud could not update one or more task-list properties.',
          );
        }
      }
    } on XmlParserException {
      throw const CalDavCalendarWriteException(
        'Nextcloud returned an invalid task-list update response.',
      );
    }
  }
}

class CalDavCalendarWriteException implements Exception {
  const CalDavCalendarWriteException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
