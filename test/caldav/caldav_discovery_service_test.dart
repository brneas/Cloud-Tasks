import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:cloud_tasks/src/caldav/caldav_discovery_service.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('discovers only calendars that support VTODO', () async {
    final depths = <String, String?>{};
    final client = MockClient((request) async {
      depths[request.url.path] = request.headers['depth'];
      switch (request.url.path) {
        case '/.well-known/caldav':
          return http.Response(_principalResponse, 207);
        case '/remote.php/dav/principals/users/alice/':
          return http.Response(_homeResponse, 207);
        case '/remote.php/dav/calendars/alice/':
          return http.Response(_calendarResponse, 207);
        default:
          return http.Response('not found', 404);
      }
    });
    final discovery = CalDavDiscoveryService(DavHttpClient(client));
    final account = NextcloudAccount(
      id: 'account',
      serverUrl: Uri(scheme: 'https', host: 'cloud.example'),
      loginName: 'alice',
      appPassword: 'app-password',
    );

    final result = await discovery.discover(account);

    expect(
      result.calendarHomeUrl,
      Uri.parse('https://cloud.example/remote.php/dav/calendars/alice/'),
    );
    expect(result.calendars, hasLength(1));
    expect(result.calendars.single.displayName, 'Personal');
    expect(result.calendars.single.color, '#0082C9');
    expect(result.calendars.single.sortOrder, 3);
    expect(result.calendars.single.isReadOnly, isFalse);
    expect(result.calendars.single.isSharedWithMe, isFalse);
    expect(result.calendars.single.canBeShared, isTrue);
    expect(
      result.calendars.single.ownerHref,
      'https://cloud.example/remote.php/dav/principals/users/alice/',
    );
    expect(
      result.calendars.single.href,
      Uri.parse(
        'https://cloud.example/remote.php/dav/calendars/alice/personal/',
      ),
    );
    expect(depths['/remote.php/dav/calendars/alice/'], '1');
  });

  test('distinguishes a shared read-only task list from an owned list',
      () async {
    final sharedResponse = _calendarResponse
        .replaceFirst('principals/users/alice/', 'principals/users/bob/')
        .replaceFirst('<d:write-content/>', '<d:read/>')
        .replaceFirst(
          '<cs:allowed-sharing-modes><cs:can-be-shared/></cs:allowed-sharing-modes>',
          '<cs:allowed-sharing-modes/>',
        );
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/.well-known/caldav':
          return http.Response(_principalResponse, 207);
        case '/remote.php/dav/principals/users/alice/':
          return http.Response(_homeResponse, 207);
        case '/remote.php/dav/calendars/alice/':
          return http.Response(sharedResponse, 207);
        default:
          return http.Response('not found', 404);
      }
    });
    final account = NextcloudAccount(
      id: 'account',
      serverUrl: Uri(scheme: 'https', host: 'cloud.example'),
      loginName: 'alice',
      appPassword: 'app-password',
    );

    final calendar = (await CalDavDiscoveryService(
      DavHttpClient(client),
    ).discover(account))
        .calendars
        .single;

    expect(calendar.isSharedWithMe, isTrue);
    expect(calendar.isReadOnly, isTrue);
    expect(calendar.canBeShared, isFalse);
  });
}

const _principalResponse = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/.well-known/caldav</d:href>
    <d:propstat><d:prop>
      <d:current-user-principal>
        <d:href>/remote.php/dav/principals/users/alice/</d:href>
      </d:current-user-principal>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';

const _homeResponse = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:response>
    <d:href>/remote.php/dav/principals/users/alice/</d:href>
    <d:propstat><d:prop>
      <c:calendar-home-set>
        <d:href>/remote.php/dav/calendars/alice/</d:href>
      </c:calendar-home-set>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';

const _calendarResponse = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:"
  xmlns:c="urn:ietf:params:xml:ns:caldav"
  xmlns:a="http://apple.com/ns/ical/"
  xmlns:cs="http://calendarserver.org/ns/">
  <d:response>
    <d:href>/remote.php/dav/calendars/alice/personal/</d:href>
    <d:propstat><d:prop>
      <d:displayname>Personal</d:displayname>
      <d:owner><d:href>/remote.php/dav/principals/users/alice/</d:href></d:owner>
      <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
      <d:current-user-privilege-set>
        <d:privilege><d:write-content/></d:privilege>
      </d:current-user-privilege-set>
      <d:sync-token>token-1</d:sync-token>
      <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>
      <a:calendar-color>#0082C9</a:calendar-color>
      <a:calendar-order>3</a:calendar-order>
      <cs:allowed-sharing-modes><cs:can-be-shared/></cs:allowed-sharing-modes>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/dav/calendars/alice/birthdays/</d:href>
    <d:propstat><d:prop>
      <d:displayname>Birthdays</d:displayname>
      <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
      <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';
