import 'package:xml/xml.dart';

const davNamespace = 'DAV:';
const calDavNamespace = 'urn:ietf:params:xml:ns:caldav';
const appleICalendarNamespace = 'http://apple.com/ns/ical/';
const ownCloudNamespace = 'http://owncloud.org/ns';
const calendarServerNamespace = 'http://calendarserver.org/ns/';

XmlElement? successfulDavProperties(XmlElement response) {
  for (final propstat in response.findElements(
    'propstat',
    namespace: davNamespace,
  )) {
    final status = propstat.getElement('status', namespace: davNamespace);
    if (status != null && RegExp(r'\s2\d\d\s').hasMatch(status.innerText)) {
      return propstat.getElement('prop', namespace: davNamespace);
    }
  }
  return null;
}

Uri resolveDavHref(Uri requestUrl, String href) {
  return requestUrl.resolve(href.trim());
}

String? elementText(
  XmlElement parent,
  String localName, {
  required String namespace,
}) {
  final element = parent.getElement(localName, namespace: namespace);
  final value = element?.innerText.trim();
  return value == null || value.isEmpty ? null : value;
}
