import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/caldav/dav_xml.dart';
import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_codec.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:cloud_tasks/src/sync/sync_contracts.dart';
import 'package:xml/xml.dart';

class CalDavTaskReader {
  const CalDavTaskReader(this._http, {VTodoCodec codec = const VTodoCodec()})
    : _codec = codec;

  final DavHttpClient _http;
  final VTodoCodec _codec;

  Future<List<TaskRecord>> readAll(TaskCalendar calendar) async {
    final response = await _http.request(
      'REPORT',
      calendar.href,
      headers: const <String, String>{
        'Accept': 'application/xml, text/xml',
        'Content-Type': 'application/xml; charset=utf-8',
        'Depth': '1',
      },
      body: _calendarQuery,
    );
    if (response.statusCode != 207) {
      throw CalDavTaskReadException(
        'Could not load ${calendar.displayName} (HTTP ${response.statusCode}).',
      );
    }

    final requestUrl = response.request?.url ?? calendar.href;
    final document = XmlDocument.parse(response.body);
    final records = <TaskRecord>[];
    for (final responseElement in document.findAllElements(
      'response',
      namespace: davNamespace,
    )) {
      final record = _recordFromResponse(
        responseElement,
        calendarId: calendar.id,
        requestUrl: requestUrl,
      );
      if (record != null) records.add(record);
    }
    return List<TaskRecord>.unmodifiable(records);
  }

  Future<CalendarDelta> readChanges(
    TaskCalendar calendar,
    String syncToken,
  ) async {
    final response = await _http.request(
      'REPORT',
      calendar.href,
      headers: const <String, String>{
        'Accept': 'application/xml, text/xml',
        'Content-Type': 'application/xml; charset=utf-8',
        'Depth': '1',
      },
      body: _syncCollection(syncToken),
    );
    if (<int>{400, 403, 405, 409, 501}.contains(response.statusCode)) {
      throw const InvalidCalDavSyncTokenException();
    }
    if (response.statusCode != 207) {
      throw CalDavTaskReadException(
        'Could not update ${calendar.displayName} '
        '(HTTP ${response.statusCode}).',
      );
    }

    final requestUrl = response.request?.url ?? calendar.href;
    final document = XmlDocument.parse(response.body);
    final changed = <TaskRecord>[];
    final deleted = <Uri>[];
    for (final responseElement in document.findAllElements(
      'response',
      namespace: davNamespace,
    )) {
      final hrefText = elementText(
        responseElement,
        'href',
        namespace: davNamespace,
      );
      if (hrefText == null) continue;
      final record = _recordFromResponse(
        responseElement,
        calendarId: calendar.id,
        requestUrl: requestUrl,
      );
      if (record != null) {
        changed.add(record);
        continue;
      }
      final status = elementText(
        responseElement,
        'status',
        namespace: davNamespace,
      );
      final hasMissingProperty = responseElement
          .findElements('propstat', namespace: davNamespace)
          .any(
            (propstat) => RegExp(r'\s404\s').hasMatch(
              elementText(propstat, 'status', namespace: davNamespace) ?? '',
            ),
          );
      if (RegExp(r'\s404\s').hasMatch(status ?? '') || hasMissingProperty) {
        deleted.add(resolveDavHref(requestUrl, hrefText));
      }
    }

    return CalendarDelta(
      changed: List<TaskRecord>.unmodifiable(changed),
      deletedHrefs: List<Uri>.unmodifiable(deleted),
      nextSyncToken:
          elementText(
            document.rootElement,
            'sync-token',
            namespace: davNamespace,
          ) ??
          syncToken,
    );
  }

  TaskRecord? _recordFromResponse(
    XmlElement responseElement, {
    required String calendarId,
    required Uri requestUrl,
  }) {
    final properties = successfulDavProperties(responseElement);
    final hrefText = elementText(
      responseElement,
      'href',
      namespace: davNamespace,
    );
    final calendarData = properties?.getElement(
      'calendar-data',
      namespace: calDavNamespace,
    );
    if (properties == null ||
        hrefText == null ||
        calendarData == null ||
        calendarData.innerText.trim().isEmpty) {
      return null;
    }
    try {
      final rawDocument = ICalendarDocument.parse(calendarData.innerText);
      return TaskRecord(
        task: _codec.decode(rawDocument, calendarId: calendarId),
        href: resolveDavHref(requestUrl, hrefText),
        etag: elementText(properties, 'getetag', namespace: davNamespace),
        rawDocument: rawDocument,
        baseDocument: rawDocument,
      );
    } on FormatException {
      return null;
    }
  }

  static String _syncCollection(String syncToken) =>
      '''<?xml version="1.0" encoding="utf-8" ?>
<d:sync-collection xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:sync-token>${_xmlEscape(syncToken)}</d:sync-token>
  <d:sync-level>1</d:sync-level>
  <d:prop>
    <d:getetag />
    <c:calendar-data />
  </d:prop>
</d:sync-collection>''';

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static const _calendarQuery = '''<?xml version="1.0" encoding="utf-8" ?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:getetag />
    <c:calendar-data />
  </d:prop>
  <c:filter>
    <c:comp-filter name="VCALENDAR">
      <c:comp-filter name="VTODO" />
    </c:comp-filter>
  </c:filter>
</c:calendar-query>''';
}

class CalDavTaskReadException implements Exception {
  const CalDavTaskReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class InvalidCalDavSyncTokenException implements Exception {
  const InvalidCalDavSyncTokenException();

  @override
  String toString() => 'The server no longer accepts the saved sync token.';
}
