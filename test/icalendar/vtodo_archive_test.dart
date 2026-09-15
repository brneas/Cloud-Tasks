import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_archive.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const archive = VTodoArchive();
  const codec = VTodoCodec();

  test('exports and imports multiple tasks without losing nested data', () {
    final first = ICalendarDocument.parse(
      'BEGIN:VCALENDAR\r\n'
      'VERSION:2.0\r\n'
      'BEGIN:VTODO\r\n'
      'UID:first\r\n'
      'SUMMARY:First\r\n'
      'X-UNKNOWN:keep\r\n'
      'BEGIN:VALARM\r\n'
      'ACTION:DISPLAY\r\n'
      'TRIGGER:-PT15M\r\n'
      'END:VALARM\r\n'
      'END:VTODO\r\n'
      'END:VCALENDAR\r\n',
    );
    final second = ICalendarDocument.parse(
      'BEGIN:VCALENDAR\r\n'
      'VERSION:2.0\r\n'
      'BEGIN:VTODO\r\n'
      'UID:second\r\n'
      'SUMMARY:Second\r\n'
      'RELATED-TO;RELTYPE=PARENT:first\r\n'
      'END:VTODO\r\n'
      'END:VCALENDAR\r\n',
    );

    final encoded = archive.encode(<ICalendarDocument>[first, second]);
    final decoded = archive.decode(encoded);

    expect(decoded, hasLength(2));
    expect(codec.decode(decoded[0]).uid, 'first');
    expect(codec.decode(decoded[1]).parentUid, 'first');
    expect(decoded[0].serialize(), contains('X-UNKNOWN:keep'));
    expect(decoded[0].serialize(), contains('BEGIN:VALARM'));
  });

  test('rejects an iCalendar file without tasks', () {
    expect(
      () => archive.decode(
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n',
      ),
      throwsFormatException,
    );
  });
}
