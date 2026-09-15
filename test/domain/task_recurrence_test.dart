import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/domain/task_recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = TaskRecurrenceService();

  test('advances both dates and decrements a finite series', () {
    final task = CloudTask(
      uid: 'weekly',
      summary: 'Weekly task',
      start: CloudTaskDate(value: DateTime(2030, 1, 7, 9), isAllDay: false),
      due: CloudTaskDate(value: DateTime(2030, 1, 7, 10), isAllDay: false),
      recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4',
    );

    final next = service.nextOccurrence(task);

    expect(next, isNotNull);
    expect(next?.start?.value, DateTime(2030, 1, 9, 9));
    expect(next?.due?.value, DateTime(2030, 1, 9, 10));
    expect(next?.recurrenceRule, 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=3');
  });

  test('stops when COUNT says the current occurrence is the last', () {
    final task = CloudTask(
      uid: 'last',
      summary: 'Last task',
      due: CloudTaskDate(value: DateTime(2030, 1, 7), isAllDay: true),
      recurrenceRule: 'FREQ=DAILY;COUNT=1',
    );

    expect(service.nextOccurrence(task), isNull);
  });

  test('preserves UTC and TZID date representation while shifting', () {
    final task = CloudTask(
      uid: 'monthly',
      summary: 'Monthly task',
      start: CloudTaskDate(
        value: DateTime(2030, 1, 14, 9),
        isAllDay: false,
        timeZoneId: 'America/New_York',
      ),
      due: CloudTaskDate(value: DateTime.utc(2030, 1, 14, 15), isAllDay: false),
      recurrenceRule: 'FREQ=MONTHLY;BYDAY=2MO',
    );

    final next = service.nextOccurrence(task);

    expect(next?.start?.timeZoneId, 'America/New_York');
    expect(next?.start?.value, DateTime(2030, 2, 11, 9));
    expect(next?.due?.value, DateTime.utc(2030, 2, 11, 15));
    expect(next?.due?.value.isUtc, isTrue);
  });
}
