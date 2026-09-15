import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';

/// Imports and exports collections of VTODO components without rewriting their
/// contents. Each imported component is wrapped in its own VCALENDAR so the
/// preservation-oriented editor can continue to work on one task at a time.
class VTodoArchive {
  const VTodoArchive();

  List<ICalendarDocument> decode(String source) {
    final archive = ICalendarDocument.parse(source);
    final components = archive.childComponents(
      'VTODO',
      parentName: 'VCALENDAR',
    );
    if (components.isEmpty) {
      throw const FormatException('The iCalendar file contains no tasks.');
    }
    return List<ICalendarDocument>.unmodifiable(
      components.map(
        (lines) => ICalendarDocument.parse(
          <String>[
            'BEGIN:VCALENDAR',
            'VERSION:2.0',
            'PRODID:-//Cloud Tasks//EN',
            ...lines,
            'END:VCALENDAR',
          ].join('\r\n'),
        ),
      ),
    );
  }

  String encode(Iterable<ICalendarDocument> documents) {
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Cloud Tasks//EN',
      'CALSCALE:GREGORIAN',
    ];
    for (final document in documents) {
      final components = document.childComponents(
        'VTODO',
        parentName: 'VCALENDAR',
      );
      if (components.isNotEmpty) {
        lines.addAll(components.first);
      }
    }
    lines.add('END:VCALENDAR');
    return ICalendarDocument.parse(lines.join('\r\n')).serialize();
  }
}
