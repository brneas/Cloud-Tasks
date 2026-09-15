import 'package:cloud_tasks/src/caldav/caldav_calendar_writer.dart';
import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('creates a VTODO collection with escaped metadata', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('', 201);
    });
    final writer = CalDavCalendarWriter(DavHttpClient(client));

    final result = await writer.create(
      accountId: 'account',
      calendarHomeUrl: Uri.parse(
        'https://cloud.example/remote.php/dav/calendars/alice/',
      ),
      collectionId: 'generated-list',
      displayName: 'Home & errands',
      color: '#12ab34',
      sortOrder: 1048576,
    );

    expect(captured.method, 'MKCALENDAR');
    expect(captured.url.path, endsWith('/generated-list/'));
    expect(captured.body, contains('<d:displayname>Home &amp; errands'));
    expect(captured.body, contains('name="VTODO"'));
    expect(captured.body, contains('#12AB34FF'));
    expect(result.displayName, 'Home & errands');
  });

  test('updates list properties with PROPPATCH', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(_multiStatus, 207);
    });
    final writer = CalDavCalendarWriter(DavHttpClient(client));

    await writer.update(
      _calendar,
      displayName: 'Renamed',
      color: '#abcdef',
      sortOrder: 42,
    );

    expect(captured.method, 'PROPPATCH');
    expect(captured.body, contains('<d:displayname>Renamed'));
    expect(captured.body, contains('<a:calendar-order>42'));
  });

  test('deletes the exact calendar collection', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('', 204);
    });

    await CalDavCalendarWriter(DavHttpClient(client)).delete(_calendar);

    expect(captured.method, 'DELETE');
    expect(captured.url, _calendar.href);
  });

  test('reports a failed property inside a 207 response', () async {
    final client = MockClient((request) async {
      return http.Response(_failedMultiStatus, 207);
    });

    await expectLater(
      CalDavCalendarWriter(DavHttpClient(client)).update(
        _calendar,
        displayName: 'Renamed',
        color: '#abcdef',
        sortOrder: 42,
      ),
      throwsA(isA<CalDavCalendarWriteException>()),
    );
  });
}

final _calendar = TaskCalendar(
  id: 'personal',
  accountId: 'account',
  href: Uri.parse(
    'https://cloud.example/remote.php/dav/calendars/alice/personal/',
  ),
  displayName: 'Personal',
  color: '#0082C9',
  sortOrder: 1,
  isReadOnly: false,
);

const _multiStatus = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:propstat><d:prop><d:displayname/></d:prop>
    <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat></d:response>
</d:multistatus>''';

const _failedMultiStatus = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:propstat><d:prop><d:displayname/></d:prop>
    <d:status>HTTP/1.1 403 Forbidden</d:status>
  </d:propstat></d:response>
</d:multistatus>''';
