import 'package:cloud_tasks/src/caldav/caldav_calendar_sharing_service.dart';
import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final calendar = TaskCalendar(
    id: 'personal',
    accountId: 'account',
    href: Uri.parse(
      'https://cloud.example/remote.php/dav/calendars/alice/personal/',
    ),
    displayName: 'Personal',
    isReadOnly: false,
    canBeShared: true,
  );

  test('reads user and group shares with their access level', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PROPFIND');
      expect(request.headers['depth'], '0');
      expect(request.body, contains('<oc:invite />'));
      return http.Response(_sharesResponse, 207);
    });

    final shares = await CalDavCalendarSharingService(DavHttpClient(client))
        .readShares(calendar);

    expect(shares, hasLength(2));
    expect(shares.first.displayName, 'Developers');
    expect(shares.first.kind, CalendarShareKind.group);
    expect(shares.first.canWrite, isFalse);
    expect(shares.last.displayName, 'Jane Doe');
    expect(shares.last.kind, CalendarShareKind.user);
    expect(shares.last.canWrite, isTrue);
  });

  test('shares with a user principal and read-write access', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response('', 200);
    });

    await CalDavCalendarSharingService(DavHttpClient(client)).share(
      calendar: calendar,
      recipientId: 'jane+tasks@example.com',
      kind: CalendarShareKind.user,
      canWrite: true,
    );

    expect(sent.method, 'POST');
    expect(
      sent.body,
      contains('principal:principals/users/jane+tasks@example.com'),
    );
    expect(sent.body, contains('<oc:read-write/>'));
  });

  test('updates to read-only by omitting read-write', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response('', 200);
    });
    const share = CalendarShare(
      principalHref: 'principal:principals/groups/developers',
      displayName: 'Developers',
      kind: CalendarShareKind.group,
      canWrite: true,
    );

    await CalDavCalendarSharingService(DavHttpClient(client))
        .updatePermission(calendar: calendar, share: share, canWrite: false);

    expect(sent.body, contains('<oc:set>'));
    expect(sent.body, isNot(contains('<oc:read-write/>')));
  });

  test('removes a share with the advertised principal href', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response('', 204);
    });
    const share = CalendarShare(
      principalHref: 'principal:principals/users/jane',
      displayName: 'Jane',
      kind: CalendarShareKind.user,
      canWrite: false,
    );

    await CalDavCalendarSharingService(DavHttpClient(client))
        .unshare(calendar: calendar, share: share);

    expect(sent.body, contains('<oc:remove>'));
    expect(sent.body, contains('principal:principals/users/jane'));
  });

  test('rejects recipient IDs that could change the principal path', () async {
    final client = MockClient((_) async => http.Response('', 200));

    await expectLater(
      CalDavCalendarSharingService(DavHttpClient(client)).share(
        calendar: calendar,
        recipientId: 'team/admin',
        kind: CalendarShareKind.group,
        canWrite: false,
      ),
      throwsA(isA<CalendarSharingException>()),
    );
  });
}

const _sharesResponse = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
  <d:response>
    <d:href>/remote.php/dav/calendars/alice/personal/</d:href>
    <d:propstat><d:prop><oc:invite>
      <oc:user>
        <d:href>principal:principals/users/jane</d:href>
        <oc:common-name>Jane Doe</oc:common-name>
        <oc:invite-accepted/>
        <oc:access><oc:read-write/></oc:access>
      </oc:user>
      <oc:user>
        <d:href>principal:principals/groups/developers</d:href>
        <oc:common-name>Developers</oc:common-name>
        <oc:invite-accepted/>
        <oc:access><oc:read/></oc:access>
      </oc:user>
    </oc:invite></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';
