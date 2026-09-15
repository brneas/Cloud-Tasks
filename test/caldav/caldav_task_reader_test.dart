import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/caldav/caldav_task_reader.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reads VTODO bodies and synchronized manual positions', () async {
    final client = MockClient((request) async {
      expect(request.method, 'REPORT');
      expect(request.headers['depth'], '1');
      expect(request.body, contains('<c:comp-filter name="VTODO" />'));
      return http.Response(_taskResponse, 207);
    });
    final reader = CalDavTaskReader(DavHttpClient(client));
    final calendar = TaskCalendar(
      id: 'personal',
      accountId: 'account',
      href: Uri(
        scheme: 'https',
        host: 'cloud.example',
        path: '/remote.php/dav/calendars/alice/personal/',
      ),
      displayName: 'Personal',
      isReadOnly: false,
    );

    final records = await reader.readAll(calendar);

    expect(records, hasLength(2));
    expect(records.map((record) => record.task.uid), <String>['later', 'first']);
    expect(
      records.map((record) => record.task.sortOrder),
      <int>[2097152, 1048576],
    );
    expect(records.last.etag, '"etag-first"');
    expect(
      records.last.href,
      Uri.parse(
        'https://cloud.example/remote.php/dav/calendars/alice/personal/first.ics',
      ),
    );
  });

  test('reads changed and deleted objects from a sync collection', () async {
    final client = MockClient((request) async {
      expect(request.method, 'REPORT');
      expect(request.body, contains('<d:sync-collection'));
      expect(request.body, contains('<d:sync-token>token-1</d:sync-token>'));
      return http.Response(_deltaResponse, 207);
    });
    final reader = CalDavTaskReader(DavHttpClient(client));
    final calendar = TaskCalendar(
      id: 'personal',
      accountId: 'account',
      href: Uri.parse(
        'https://cloud.example/remote.php/dav/calendars/alice/personal/',
      ),
      displayName: 'Personal',
      isReadOnly: false,
    );

    final delta = await reader.readChanges(calendar, 'token-1');

    expect(delta.changed.single.task.uid, 'changed');
    expect(delta.changed.single.task.sortOrder, 3145728);
    expect(
      delta.deletedHrefs.single,
      calendar.href.resolve('deleted.ics'),
    );
    expect(delta.nextSyncToken, 'token-2');
  });

  test('identifies an expired sync token so a full query can recover', () {
    final reader = CalDavTaskReader(
      DavHttpClient(MockClient((request) async => http.Response('', 403))),
    );
    final calendar = TaskCalendar(
      id: 'personal',
      accountId: 'account',
      href: Uri.parse('https://cloud.example/calendars/alice/personal/'),
      displayName: 'Personal',
      isReadOnly: false,
    );

    expect(
      reader.readChanges(calendar, 'expired'),
      throwsA(isA<InvalidCalDavSyncTokenException>()),
    );
  });
}

const _deltaResponse = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:response>
    <d:href>changed.ics</d:href>
    <d:propstat><d:prop>
      <d:getetag>&quot;changed-etag&quot;</d:getetag>
      <c:calendar-data><![CDATA[BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:changed
SUMMARY:Changed
X-APPLE-SORT-ORDER:3145728
END:VTODO
END:VCALENDAR
]]></c:calendar-data>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>deleted.ics</d:href>
    <d:status>HTTP/1.1 404 Not Found</d:status>
  </d:response>
  <d:sync-token>token-2</d:sync-token>
</d:multistatus>''';

const _taskResponse = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:response>
    <d:href>/remote.php/dav/calendars/alice/personal/later.ics</d:href>
    <d:propstat><d:prop>
      <d:getetag>&quot;etag-later&quot;</d:getetag>
      <c:calendar-data><![CDATA[BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:later
SUMMARY:Later
X-APPLE-SORT-ORDER:2097152
END:VTODO
END:VCALENDAR
]]></c:calendar-data>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/dav/calendars/alice/personal/first.ics</d:href>
    <d:propstat><d:prop>
      <d:getetag>&quot;etag-first&quot;</d:getetag>
      <c:calendar-data><![CDATA[BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:first
SUMMARY:First
X-APPLE-SORT-ORDER:1048576
END:VTODO
END:VCALENDAR
]]></c:calendar-data>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';
