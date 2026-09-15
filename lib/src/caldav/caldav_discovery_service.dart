import 'package:cloud_tasks/src/account/login_flow_v2.dart';
import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/caldav/dav_xml.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class CalDavDiscoveryService {
  const CalDavDiscoveryService(this._http);

  final DavHttpClient _http;

  Future<CalDavDiscoveryResult> discover(NextcloudAccount account) async {
    final wellKnown = account.serverUrl.replace(
      path: '/.well-known/caldav',
      query: null,
      fragment: null,
    );

    var principalResponse = await _propfind(wellKnown, _principalRequest);
    if (principalResponse.statusCode == 404 ||
        principalResponse.statusCode == 405) {
      final fallback = LoginFlowV2.appendPath(
        account.serverUrl,
        'remote.php/dav',
      );
      principalResponse = await _propfind(fallback, _principalRequest);
    }
    _requireMultiStatus(principalResponse, 'discover the current user');

    final principalRequestUrl = principalResponse.request?.url ?? wellKnown;
    final principalUrl = _readHrefProperty(
      principalResponse.body,
      principalRequestUrl,
      'current-user-principal',
      propertyNamespace: davNamespace,
    );

    final homeResponse = await _propfind(principalUrl, _calendarHomeRequest);
    _requireMultiStatus(homeResponse, 'discover the calendar home');
    final homeUrl = _readHrefProperty(
      homeResponse.body,
      homeResponse.request?.url ?? principalUrl,
      'calendar-home-set',
      propertyNamespace: calDavNamespace,
    );

    final calendarsResponse = await _propfind(
      homeUrl,
      _calendarListRequest,
      depth: '1',
    );
    _requireMultiStatus(calendarsResponse, 'load task lists');
    final calendars = _parseCalendars(
      calendarsResponse.body,
      calendarsResponse.request?.url ?? homeUrl,
      account.id,
      principalUrl,
    );

    return CalDavDiscoveryResult(
      principalUrl: principalUrl,
      calendarHomeUrl: homeUrl,
      calendars: calendars,
    );
  }

  Future<http.Response> _propfind(Uri url, String body, {String depth = '0'}) {
    return _http.request(
      'PROPFIND',
      url,
      headers: <String, String>{
        'Accept': 'application/xml, text/xml',
        'Content-Type': 'application/xml; charset=utf-8',
        'Depth': depth,
      },
      body: body,
    );
  }

  static Uri _readHrefProperty(
    String body,
    Uri requestUrl,
    String propertyName, {
    required String propertyNamespace,
  }) {
    final document = XmlDocument.parse(body);
    for (final response in document.findAllElements(
      'response',
      namespace: davNamespace,
    )) {
      final properties = successfulDavProperties(response);
      final property = properties?.getElement(
        propertyName,
        namespace: propertyNamespace,
      );
      final href = property?.getElement('href', namespace: davNamespace);
      if (href != null && href.innerText.trim().isNotEmpty) {
        return resolveDavHref(requestUrl, href.innerText);
      }
    }
    throw CalDavDiscoveryException(
      'Nextcloud did not advertise $propertyName.',
    );
  }

  static List<TaskCalendar> _parseCalendars(
    String body,
    Uri requestUrl,
    String accountId,
    Uri principalUrl,
  ) {
    final document = XmlDocument.parse(body);
    final calendars = <TaskCalendar>[];
    for (final response in document.findAllElements(
      'response',
      namespace: davNamespace,
    )) {
      final properties = successfulDavProperties(response);
      if (properties == null || !_isTaskCalendar(properties)) {
        continue;
      }

      final hrefText = response
          .getElement('href', namespace: davNamespace)
          ?.innerText
          .trim();
      if (hrefText == null || hrefText.isEmpty) {
        continue;
      }
      final href = resolveDavHref(requestUrl, hrefText);
      final displayName =
          elementText(properties, 'displayname', namespace: davNamespace) ??
              _fallbackDisplayName(href);
      final color = elementText(
        properties,
        'calendar-color',
        namespace: appleICalendarNamespace,
      );
      final orderValue = elementText(
        properties,
        'calendar-order',
        namespace: appleICalendarNamespace,
      );
      final syncToken = elementText(
        properties,
        'sync-token',
        namespace: davNamespace,
      );
      final ownerText = properties
          .getElement('owner', namespace: davNamespace)
          ?.getElement('href', namespace: davNamespace)
          ?.innerText
          .trim();
      final ownerHref = ownerText == null || ownerText.isEmpty
          ? null
          : resolveDavHref(requestUrl, ownerText).toString();
      final normalizedPrincipal = _normalizeCollectionHref(
        principalUrl.toString(),
      );
      final normalizedOwner =
          ownerHref == null ? null : _normalizeCollectionHref(ownerHref);
      final sharingModes = properties.getElement(
        'allowed-sharing-modes',
        namespace: calendarServerNamespace,
      );
      final canBeShared = sharingModes
              ?.findElements(
                'can-be-shared',
                namespace: calendarServerNamespace,
              )
              .isNotEmpty ??
          false;

      calendars.add(
        TaskCalendar(
          id: href.toString(),
          accountId: accountId,
          href: href,
          displayName: displayName,
          color: color,
          sortOrder: int.tryParse(orderValue ?? ''),
          isReadOnly: !_canWrite(properties),
          syncToken: syncToken,
          ownerHref: ownerHref,
          isSharedWithMe:
              normalizedOwner != null && normalizedOwner != normalizedPrincipal,
          canBeShared: canBeShared,
        ),
      );
    }

    calendars.sort((left, right) {
      final leftOrder = left.sortOrder;
      final rightOrder = right.sortOrder;
      if (leftOrder == null && rightOrder == null) {
        return left.displayName.compareTo(right.displayName);
      }
      if (leftOrder == null) {
        return 1;
      }
      if (rightOrder == null) {
        return -1;
      }
      return leftOrder.compareTo(rightOrder);
    });
    return List<TaskCalendar>.unmodifiable(calendars);
  }

  static bool _isTaskCalendar(XmlElement properties) {
    final resourceType = properties.getElement(
      'resourcetype',
      namespace: davNamespace,
    );
    final isCalendar = resourceType
            ?.findElements('calendar', namespace: calDavNamespace)
            .isNotEmpty ??
        false;
    if (!isCalendar) {
      return false;
    }

    final supported = properties.getElement(
      'supported-calendar-component-set',
      namespace: calDavNamespace,
    );
    return supported?.findElements('comp', namespace: calDavNamespace).any(
              (component) =>
                  component.getAttribute('name')?.toUpperCase() == 'VTODO',
            ) ??
        false;
  }

  static bool _canWrite(XmlElement properties) {
    final privileges = properties.getElement(
      'current-user-privilege-set',
      namespace: davNamespace,
    );
    if (privileges == null) {
      return false;
    }
    return privileges
            .findAllElements('all', namespace: davNamespace)
            .isNotEmpty ||
        privileges
            .findAllElements('write', namespace: davNamespace)
            .isNotEmpty ||
        privileges
            .findAllElements('write-content', namespace: davNamespace)
            .isNotEmpty;
  }

  static String _fallbackDisplayName(Uri href) {
    final segments = href.pathSegments.where((segment) => segment.isNotEmpty);
    return segments.isEmpty
        ? 'Tasks'
        : Uri.decodeComponent(segments.last.replaceAll('-', ' '));
  }

  static String _normalizeCollectionHref(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  static void _requireMultiStatus(http.Response response, String operation) {
    if (response.statusCode != 207) {
      throw CalDavDiscoveryException(
        'Could not $operation (HTTP ${response.statusCode}).',
      );
    }
  }

  static const _principalRequest = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop><d:current-user-principal /></d:prop>
</d:propfind>''';

  static const _calendarHomeRequest = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><c:calendar-home-set /></d:prop>
</d:propfind>''';

  static const _calendarListRequest = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:"
            xmlns:c="urn:ietf:params:xml:ns:caldav"
            xmlns:a="http://apple.com/ns/ical/"
            xmlns:oc="http://owncloud.org/ns"
            xmlns:cs="http://calendarserver.org/ns/">
  <d:prop>
    <d:displayname />
    <d:owner />
    <d:resourcetype />
    <d:current-user-privilege-set />
    <d:sync-token />
    <c:supported-calendar-component-set />
    <a:calendar-color />
    <a:calendar-order />
    <oc:invite />
    <cs:allowed-sharing-modes />
  </d:prop>
</d:propfind>''';
}

class CalDavDiscoveryException implements Exception {
  const CalDavDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}
