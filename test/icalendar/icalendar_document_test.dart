import 'dart:io';

import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ICalendarDocument', () {
    test('unfolds content lines and preserves unknown properties', () {
      final source = File('test/fixtures/ordered_task.ics').readAsStringSync();
      final document = ICalendarDocument.parse(source);

      expect(
        document.firstProperty('DESCRIPTION')?.value,
        contains('another client and must remain'),
      );

      final updated = const VTodoCodec().writeManualOrder(document, 42);
      final serialized = updated.serialize();

      expect(serialized, contains('X-APPLE-SORT-ORDER:42'));
      expect(
        serialized,
        contains('X-EXPERIMENTAL-PROPERTY;CLIENT="another:client":keep-me'),
      );
    });

    test('folds output by UTF-8 octets without losing Unicode', () {
      final summary = List<String>.filled(50, '🌱').join();
      const base = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:unicode\r\n'
          'SUMMARY:placeholder\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';

      final document = const VTodoCodec().writeSummary(
        ICalendarDocument.parse(base),
        summary,
      );
      final reparsed = ICalendarDocument.parse(document.serialize());

      expect(const VTodoCodec().decode(reparsed).summary, summary);
    });

    test('maps Nextcloud manual order and parent UID', () {
      final source = File('test/fixtures/ordered_task.ics').readAsStringSync();
      final task = const VTodoCodec().decode(
        ICalendarDocument.parse(source),
        calendarId: 'personal',
      );

      expect(task.uid, 'task-2');
      expect(task.summary, 'Second task');
      expect(task.calendarId, 'personal');
      expect(task.parentUid, 'parent-1');
      expect(task.sortOrder, 2097152);
    });

    test('writes completion fields, UTC timestamps, and preserves extensions',
        () {
      final source = File('test/fixtures/ordered_task.ics').readAsStringSync();
      final completed = const VTodoCodec().writeCompletion(
        ICalendarDocument.parse(source),
        isCompleted: true,
        now: DateTime.utc(2026, 9, 14, 12, 34, 56),
      );
      final serialized = completed.serialize();

      expect(completed.firstProperty('STATUS')?.value, 'COMPLETED');
      expect(completed.firstProperty('PERCENT-COMPLETE')?.value, '100');
      expect(completed.firstProperty('COMPLETED')?.value, '20260914T123456Z');
      expect(completed.firstProperty('LAST-MODIFIED')?.value,
          '20260914T123456Z');
      expect(completed.firstProperty('DTSTAMP')?.value, '20260914T123456Z');
      expect(serialized, contains('X-EXPERIMENTAL-PROPERTY'));
    });

    test('reopening removes only the VTODO completion timestamp', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:completed\r\n'
          'SUMMARY:Completed task\r\n'
          'STATUS:COMPLETED\r\n'
          'PERCENT-COMPLETE:100\r\n'
          'COMPLETED:20260913T120000Z\r\n'
          'BEGIN:VALARM\r\n'
          'COMPLETED:keep-nested-extension\r\n'
          'END:VALARM\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';
      final reopened = const VTodoCodec().writeCompletion(
        ICalendarDocument.parse(source),
        isCompleted: false,
        now: DateTime.utc(2026, 9, 14),
      );

      expect(reopened.firstProperty('STATUS')?.value, 'NEEDS-ACTION');
      expect(reopened.firstProperty('PERCENT-COMPLETE')?.value, '0');
      expect(reopened.firstProperty('COMPLETED'), isNull);
      expect(reopened.serialize(), contains('COMPLETED:keep-nested-extension'));
    });

    test('inserts new task properties before nested components', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:nested\r\n'
          'SUMMARY:Nested\r\n'
          'BEGIN:VALARM\r\n'
          'ACTION:DISPLAY\r\n'
          'TRIGGER:-PT15M\r\n'
          'END:VALARM\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';
      final updated = ICalendarDocument.parse(source).addProperty(
        'LOCATION',
        'Workshop',
      );
      final lines = updated.logicalLines;

      expect(
        lines.indexOf('LOCATION:Workshop'),
        lessThan(lines.indexOf('BEGIN:VALARM')),
      );
      expect(updated.firstProperty('LOCATION')?.value, 'Workshop');
      expect(
        updated.firstProperty('TRIGGER', componentName: 'VALARM')?.value,
        '-PT15M',
      );
    });

    test('creates a Nextcloud-compatible task and decodes task details', () {
      const codec = VTodoCodec();
      final created = codec.create(
        uid: 'new-task',
        summary: 'New, useful task',
        sortOrder: 1048576,
        now: DateTime.utc(2026, 9, 15, 1, 2, 3),
        parentUid: 'parent-task',
      );
      var detailed = codec.writeDescriptionAndStamp(
        created,
        'A note with, punctuation',
        now: DateTime.utc(2026, 9, 15, 2),
      );
      detailed = codec.writeDateAndStamp(
        detailed,
        'DUE',
        DateTime(2026, 10, 3),
        now: DateTime.utc(2026, 9, 15, 2),
      );
      detailed = codec.writePriorityAndStamp(
        detailed,
        1,
        now: DateTime.utc(2026, 9, 15, 2),
      );
      final task = codec.decode(detailed, calendarId: 'personal');

      expect(task.uid, 'new-task');
      expect(task.summary, 'New, useful task');
      expect(task.parentUid, 'parent-task');
      expect(task.description, 'A note with, punctuation');
      expect(task.due?.isAllDay, isTrue);
      expect(task.due?.value, DateTime(2026, 10, 3));
      expect(task.priority, 1);
      expect(detailed.serialize(), contains('DUE;VALUE=DATE:20261003'));
      expect(detailed.serialize(), contains('CREATED:20260915T010203Z'));

      final remoteWithTimedDue = ICalendarDocument.parse(
        detailed.serialize().replaceFirst(
              'DUE;VALUE=DATE:20261003',
              'DUE;TZID=America/New_York:20261004T120000',
            ),
      );
      final rebased = remoteWithTimedDue.copyPropertyFrom(detailed, 'DUE');
      expect(rebased.serialize(), contains('DUE;VALUE=DATE:20261003'));
      expect(rebased.serialize(), isNot(contains('DUE;TZID=')));
    });

    test('clears editable details without removing unknown properties', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:details\r\n'
          'SUMMARY:Details\r\n'
          'DESCRIPTION:Remove me\r\n'
          'DUE;TZID=America/New_York:20260920T120000\r\n'
          'PRIORITY:5\r\n'
          'X-UNKNOWN:keep\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';
      const codec = VTodoCodec();
      var document = codec.writeDescriptionAndStamp(
        ICalendarDocument.parse(source),
        '',
        now: DateTime.utc(2026, 9, 15),
      );
      document = codec.writeDateAndStamp(
        document,
        'DUE',
        null,
        now: DateTime.utc(2026, 9, 15),
      );
      document = codec.writePriorityAndStamp(
        document,
        null,
        now: DateTime.utc(2026, 9, 15),
      );

      expect(document.firstProperty('DESCRIPTION'), isNull);
      expect(document.firstProperty('DUE'), isNull);
      expect(document.firstProperty('PRIORITY'), isNull);
      expect(document.serialize(), contains('X-UNKNOWN:keep'));
    });

    test('maps advanced task fields and replaces only the display alarm', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:advanced\r\n'
          'SUMMARY:Advanced\r\n'
          r'CATEGORIES:Home,Needs\,tools'
          '\r\n'
          'LOCATION:Workshop\r\n'
          'URL:https://cloud.example/task/advanced\r\n'
          'RRULE:FREQ=WEEKLY\r\n'
          'BEGIN:VALARM\r\n'
          'ACTION:DISPLAY\r\n'
          'TRIGGER;RELATED=END:-PT15M\r\n'
          'DESCRIPTION:Old reminder\r\n'
          'END:VALARM\r\n'
          'BEGIN:X-CUSTOM\r\n'
          'X-KEEP:nested\r\n'
          'END:X-CUSTOM\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';
      const codec = VTodoCodec();
      final decoded = codec.decode(ICalendarDocument.parse(source));

      expect(decoded.categories, <String>['Home', 'Needs,tools']);
      expect(decoded.location, 'Workshop');
      expect(decoded.url.toString(), 'https://cloud.example/task/advanced');
      expect(decoded.recurrenceRule, 'FREQ=WEEKLY');
      expect(decoded.reminder?.trigger, '-PT15M');
      expect(decoded.reminder?.relatedToEnd, isTrue);

      var updated = codec.writeCategoriesAndStamp(
        ICalendarDocument.parse(source),
        const <String>['Work', 'Needs,tools'],
        now: DateTime.utc(2026, 9, 15),
      );
      updated = codec.writeReminderAndStamp(
        updated,
        const Duration(hours: 1),
        now: DateTime.utc(2026, 9, 15),
      );

      expect(updated.serialize(), contains(r'CATEGORIES:Work,Needs\,tools'));
      expect(updated.serialize(), contains('TRIGGER;RELATED=END:-PT1H'));
      expect(updated.serialize(), contains('BEGIN:X-CUSTOM'));
      expect(updated.serialize(), contains('X-KEEP:nested'));
      expect(updated.serialize(), contains('END:X-CUSTOM'));
    });

    test('round-trips timed dates and multiple independent alarms', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:schedule\r\n'
          'SUMMARY:Scheduled task\r\n'
          'DTSTART;TZID=America/New_York:20261003T090000\r\n'
          'DUE:20261003T150000Z\r\n'
          'BEGIN:VALARM\r\n'
          'ACTION:DISPLAY\r\n'
          'TRIGGER:-PT30M\r\n'
          'DESCRIPTION:Start soon\r\n'
          'END:VALARM\r\n'
          'BEGIN:VALARM\r\n'
          'ACTION:DISPLAY\r\n'
          'TRIGGER;RELATED=END:-PT10M\r\n'
          'DESCRIPTION:Due soon\r\n'
          'END:VALARM\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';
      const codec = VTodoCodec();
      final task = codec.decode(ICalendarDocument.parse(source));

      expect(task.start?.isAllDay, isFalse);
      expect(task.start?.timeZoneId, 'America/New_York');
      expect(task.start?.value, DateTime(2026, 10, 3, 9));
      expect(task.due?.value, DateTime.utc(2026, 10, 3, 15));
      expect(task.reminders, hasLength(2));
      expect(task.reminders.first.description, 'Start soon');
      expect(task.reminders.last.relatedToEnd, isTrue);

      var updated = codec.writeTaskDateAndStamp(
        ICalendarDocument.parse(source),
        'DTSTART',
        CloudTaskDate(
          value: DateTime(2026, 10, 4, 9, 30),
          isAllDay: false,
          timeZoneId: 'America/New_York',
        ),
        now: DateTime.utc(2026, 9, 15),
      );
      updated = codec.writeRemindersAndStamp(
        updated,
        const <CloudTaskReminder>[
          CloudTaskReminder(
            trigger: '-PT1H',
            relatedToEnd: false,
            description: 'Starts in one hour',
          ),
          CloudTaskReminder(
            trigger: '-P1D',
            relatedToEnd: true,
            description: 'Due tomorrow',
          ),
        ],
        now: DateTime.utc(2026, 9, 15),
      );
      final serialized = updated.serialize();

      expect(
        serialized,
        contains('DTSTART;TZID=America/New_York:20261004T093000'),
      );
      expect('BEGIN:VALARM'.allMatches(serialized), hasLength(2));
      expect(serialized, contains('TRIGGER:-PT1H'));
      expect(serialized, contains('TRIGGER;RELATED=END:-P1D'));
    });

    test('retains unsupported alarm fields when a reminder is kept', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:custom-alarm\r\n'
          'SUMMARY:Custom alarm\r\n'
          'BEGIN:VALARM\r\n'
          'ACTION:DISPLAY\r\n'
          'TRIGGER;VALUE=DATE-TIME:20300101T120000Z\r\n'
          'REPEAT:2\r\n'
          'DURATION:PT5M\r\n'
          'X-ALARM-EXTENSION:keep\r\n'
          'END:VALARM\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';
      const codec = VTodoCodec();
      final document = ICalendarDocument.parse(source);
      final task = codec.decode(document);
      final updated = codec.writeRemindersAndStamp(
        document,
        task.reminders,
        now: DateTime.utc(2026, 9, 15),
      );

      expect(updated.serialize(), contains('REPEAT:2'));
      expect(updated.serialize(), contains('DURATION:PT5M'));
      expect(updated.serialize(), contains('X-ALARM-EXTENSION:keep'));
      expect(
        updated.serialize(),
        contains('TRIGGER;VALUE=DATE-TIME:20300101T120000Z'),
      );
    });

    test('writes a new absolute reminder as an RFC date-time trigger', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:absolute-alarm\r\n'
          'SUMMARY:Absolute alarm\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';
      const codec = VTodoCodec();
      final updated = codec.writeRemindersAndStamp(
        ICalendarDocument.parse(source),
        const <CloudTaskReminder>[
          CloudTaskReminder(
            trigger: '20300101T120000Z',
            relatedToEnd: false,
          ),
        ],
        now: DateTime.utc(2026, 9, 15),
      );

      expect(
        updated.serialize(),
        contains('TRIGGER;VALUE=DATE-TIME:20300101T120000Z'),
      );
      expect(
        codec.decode(updated).reminders.single.trigger,
        '20300101T120000Z',
      );
    });

    test('forks a clean next occurrence without losing task metadata', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:old-occurrence\r\n'
          'SUMMARY:Recurring task\r\n'
          'CREATED:20260915T000000Z\r\n'
          'STATUS:COMPLETED\r\n'
          'PERCENT-COMPLETE:100\r\n'
          'COMPLETED:20261001T120000Z\r\n'
          'DTSTART;VALUE=DATE:20261001\r\n'
          'DUE;VALUE=DATE:20261001\r\n'
          'RRULE:FREQ=DAILY;COUNT=3\r\n'
          'CATEGORIES:Home\r\n'
          'BEGIN:VALARM\r\n'
          'ACTION:DISPLAY\r\n'
          'TRIGGER;RELATED=END:-PT1H\r\n'
          'END:VALARM\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';
      const codec = VTodoCodec();
      final next = codec.createNextOccurrence(
        ICalendarDocument.parse(source),
        uid: 'new-occurrence',
        start: CloudTaskDate(
          value: DateTime(2026, 10, 2),
          isAllDay: true,
        ),
        due: CloudTaskDate(
          value: DateTime(2026, 10, 2),
          isAllDay: true,
        ),
        recurrenceRule: 'FREQ=DAILY;COUNT=2',
        now: DateTime.utc(2026, 10, 1, 12),
      );

      expect(next.firstProperty('UID')?.value, 'new-occurrence');
      expect(next.firstProperty('STATUS')?.value, 'NEEDS-ACTION');
      expect(next.firstProperty('PERCENT-COMPLETE')?.value, '0');
      expect(next.firstProperty('COMPLETED'), isNull);
      expect(next.firstProperty('RRULE')?.value, 'FREQ=DAILY;COUNT=2');
      expect(next.serialize(), contains('DTSTART;VALUE=DATE:20261002'));
      expect(next.serialize(), contains('DUE;VALUE=DATE:20261002'));
      expect(next.serialize(), contains('CATEGORIES:Home'));
      expect(next.serialize(), contains('TRIGGER;RELATED=END:-PT1H'));
    });

    test('reparents a task without discarding unrelated relationships', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:child\r\n'
          'SUMMARY:Child\r\n'
          'RELATED-TO;RELTYPE=PARENT:old-parent\r\n'
          'RELATED-TO;RELTYPE=SIBLING:keep-this\r\n'
          'X-APPLE-SORT-ORDER:10\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';
      final updated = const VTodoCodec().writeParentAndOrderAndStamp(
        ICalendarDocument.parse(source),
        parentUid: 'new-parent',
        sortOrder: 42,
        now: DateTime.utc(2026, 9, 15),
      );

      expect(
        updated.serialize(),
        contains('RELATED-TO;RELTYPE=PARENT:new-parent'),
      );
      expect(
        updated.serialize(),
        contains('RELATED-TO;RELTYPE=SIBLING:keep-this'),
      );
      expect(updated.serialize(), isNot(contains('old-parent')));
      expect(updated.firstProperty('X-APPLE-SORT-ORDER')?.value, '42');
    });

    test('keeps status and percent complete consistent', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:progress\r\n'
          'SUMMARY:Progress\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR\r\n';
      const codec = VTodoCodec();
      final halfway = codec.writeProgressAndStamp(
        ICalendarDocument.parse(source),
        50,
        now: DateTime.utc(2026, 9, 15),
      );
      final completed = codec.writeProgressAndStamp(
        halfway,
        100,
        now: DateTime.utc(2026, 9, 15, 1),
      );

      expect(halfway.firstProperty('STATUS')?.value, 'IN-PROCESS');
      expect(halfway.firstProperty('PERCENT-COMPLETE')?.value, '50');
      expect(completed.firstProperty('STATUS')?.value, 'COMPLETED');
      expect(completed.firstProperty('PERCENT-COMPLETE')?.value, '100');
      expect(completed.firstProperty('COMPLETED'), isNotNull);
    });
  });
}
