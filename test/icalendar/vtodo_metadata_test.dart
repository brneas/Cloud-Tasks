import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = VTodoCodec();

  test('decodes privacy and lifecycle timestamps', () {
    final task = codec.decode(
      ICalendarDocument.parse(
        'BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'BEGIN:VTODO\r\n'
        'UID:metadata\r\n'
        'SUMMARY:Metadata\r\n'
        'CLASS:CONFIDENTIAL\r\n'
        'CREATED:20260914T100000Z\r\n'
        'LAST-MODIFIED:20260914T110000Z\r\n'
        'COMPLETED:20260914T120000Z\r\n'
        'END:VTODO\r\n'
        'END:VCALENDAR\r\n',
      ),
    );

    expect(task.privacy, CloudTaskPrivacy.confidential);
    expect(task.createdAt, DateTime.utc(2026, 9, 14, 10));
    expect(task.lastModifiedAt, DateTime.utc(2026, 9, 14, 11));
    expect(task.completedAt, DateTime.utc(2026, 9, 14, 12));
  });

  test('writes and clears task privacy without losing extensions', () {
    final source = ICalendarDocument.parse(
      'BEGIN:VCALENDAR\r\n'
      'VERSION:2.0\r\n'
      'BEGIN:VTODO\r\n'
      'UID:privacy\r\n'
      'SUMMARY:Privacy\r\n'
      'X-CUSTOM:keep\r\n'
      'END:VTODO\r\n'
      'END:VCALENDAR\r\n',
    );
    final private = codec.writePrivacyAndStamp(
      source,
      CloudTaskPrivacy.private,
      now: DateTime.utc(2026, 9, 14),
    );
    final cleared = codec.writePrivacyAndStamp(
      private,
      null,
      now: DateTime.utc(2026, 9, 14, 1),
    );

    expect(private.firstProperty('CLASS')?.value, 'PRIVATE');
    expect(cleared.firstProperty('CLASS'), isNull);
    expect(cleared.serialize(), contains('X-CUSTOM:keep'));
  });

  test('duplicates a completed task as an independent open task', () {
    final duplicate = codec.duplicate(
      ICalendarDocument.parse(
        'BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'BEGIN:VTODO\r\n'
        'UID:old\r\n'
        'SUMMARY:Copy me\r\n'
        'STATUS:COMPLETED\r\n'
        'PERCENT-COMPLETE:100\r\n'
        'COMPLETED:20260914T100000Z\r\n'
        'X-CUSTOM:keep\r\n'
        'END:VTODO\r\n'
        'END:VCALENDAR\r\n',
      ),
      uid: 'new',
      parentUid: 'parent',
      sortOrder: 42,
      now: DateTime.utc(2026, 9, 15),
    );

    expect(duplicate.firstProperty('UID')?.value, 'new');
    expect(duplicate.firstProperty('STATUS')?.value, 'NEEDS-ACTION');
    expect(duplicate.firstProperty('COMPLETED'), isNull);
    expect(duplicate.firstProperty('X-APPLE-SORT-ORDER')?.value, '42');
    expect(duplicate.serialize(), contains('X-CUSTOM:keep'));
  });

  test('writes, decodes, and clears Nextcloud pinned state', () {
    final source = ICalendarDocument.parse(
      'BEGIN:VCALENDAR\r\n'
      'VERSION:2.0\r\n'
      'BEGIN:VTODO\r\n'
      'UID:pinned\r\n'
      'SUMMARY:Pinned\r\n'
      'END:VTODO\r\n'
      'END:VCALENDAR\r\n',
    );
    final pinned = codec.writePinnedAndStamp(
      source,
      true,
      now: DateTime.utc(2026, 9, 15),
    );
    final unpinned = codec.writePinnedAndStamp(
      pinned,
      false,
      now: DateTime.utc(2026, 9, 15, 1),
    );

    expect(codec.decode(pinned).pinned, isTrue);
    expect(pinned.firstProperty('X-PINNED')?.value, 'true');
    expect(codec.decode(unpinned).pinned, isFalse);
    expect(unpinned.firstProperty('X-PINNED'), isNull);
  });

  test('edits and clears completion dates with consistent task state', () {
    final source = ICalendarDocument.parse(
      'BEGIN:VCALENDAR\r\n'
      'VERSION:2.0\r\n'
      'BEGIN:VTODO\r\n'
      'UID:completed-at\r\n'
      'SUMMARY:Completed at\r\n'
      'STATUS:NEEDS-ACTION\r\n'
      'PERCENT-COMPLETE:0\r\n'
      'END:VTODO\r\n'
      'END:VCALENDAR\r\n',
    );
    final completed = codec.writeCompletedAtAndStamp(
      source,
      DateTime.utc(2026, 9, 14, 12, 30),
      now: DateTime.utc(2026, 9, 15),
    );
    final cleared = codec.writeCompletedAtAndStamp(
      completed,
      null,
      now: DateTime.utc(2026, 9, 15, 1),
    );

    expect(completed.firstProperty('STATUS')?.value, 'COMPLETED');
    expect(completed.firstProperty('PERCENT-COMPLETE')?.value, '100');
    expect(completed.firstProperty('COMPLETED')?.value, '20260914T123000Z');
    expect(cleared.firstProperty('COMPLETED'), isNull);
    expect(cleared.firstProperty('STATUS')?.value, 'IN-PROCESS');
    expect(cleared.firstProperty('PERCENT-COMPLETE')?.value, '99');
    expect(
      () => codec.writeCompletedAtAndStamp(
        source,
        DateTime.utc(2026, 9, 16),
        now: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
  });

  test('clears status without leaving a completed task behind', () {
    final source = ICalendarDocument.parse(
      'BEGIN:VCALENDAR\r\n'
      'VERSION:2.0\r\n'
      'BEGIN:VTODO\r\n'
      'UID:clear-status\r\n'
      'SUMMARY:Clear status\r\n'
      'STATUS:COMPLETED\r\n'
      'PERCENT-COMPLETE:100\r\n'
      'COMPLETED:20260914T120000Z\r\n'
      'END:VTODO\r\n'
      'END:VCALENDAR\r\n',
    );
    final cleared = codec.writeStatusAndProgress(
      source,
      status: null,
      percentComplete: 100,
      now: DateTime.utc(2026, 9, 15),
    );

    expect(cleared.firstProperty('STATUS'), isNull);
    expect(cleared.firstProperty('COMPLETED'), isNull);
    expect(cleared.firstProperty('PERCENT-COMPLETE')?.value, '99');
  });
}
