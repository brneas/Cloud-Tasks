import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/domain/task_view_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const filter = TaskViewFilter();
  final now = DateTime(2030, 5, 4, 12);

  test('matches the date-based smart views', () {
    final overdue = _task('Overdue', due: DateTime(2030, 5, 3));
    final today = _task('Today', due: DateTime(2030, 5, 4, 17));
    final nextWeek = _task('Next week', due: DateTime(2030, 5, 10));
    final later = _task('Later', due: DateTime(2030, 5, 20));

    expect(
      filter.matchesSmartView(SmartTaskView.overdue, overdue, now: now),
      isTrue,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.today, today, now: now),
      isTrue,
    );
    expect(
      filter.matchesSmartView(
        SmartTaskView.nextSevenDays,
        nextWeek,
        now: now,
      ),
      isTrue,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.nextSevenDays, later, now: now),
      isFalse,
    );
  });

  test('matches Nextcloud current, today, and week collection boundaries', () {
    final undated = _task('Undated');
    final started = _task('Started', start: DateTime(2030, 5, 4, 11));
    final future = _task('Future', start: DateTime(2030, 5, 5, 11));
    final overdue = _task('Overdue today', due: DateTime(2030, 5, 3));

    expect(
      filter.matchesSmartView(SmartTaskView.current, undated, now: now),
      isTrue,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.current, started, now: now),
      isTrue,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.current, future, now: now),
      isFalse,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.today, overdue, now: now),
      isTrue,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.nextSevenDays, overdue, now: now),
      isTrue,
    );
  });

  test('completed view includes completed and cancelled tasks only', () {
    final completed = _task('Done', status: CloudTaskStatus.completed);
    final timestampOnly = CloudTask(
      uid: 'timestamp-only',
      summary: 'Timestamp only',
      completedAt: DateTime.utc(2030, 5, 1),
    );
    final cancelled = _task('Dropped', status: CloudTaskStatus.cancelled);
    final open = _task('Open');

    expect(
      filter.matchesSmartView(SmartTaskView.completed, completed, now: now),
      isTrue,
    );
    expect(
      filter.matchesSmartView(
        SmartTaskView.completed,
        timestampOnly,
        now: now,
      ),
      isTrue,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.completed, cancelled, now: now),
      isTrue,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.completed, open, now: now),
      isFalse,
    );
  });

  test('important view includes only open high-priority tasks', () {
    final highest = _task('Highest', priority: 1);
    final high = _task('High', priority: 4);
    final medium = _task('Medium', priority: 5);
    final completed = _task(
      'Completed important',
      priority: 1,
      status: CloudTaskStatus.completed,
    );

    expect(
      filter.matchesSmartView(SmartTaskView.important, highest, now: now),
      isTrue,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.important, high, now: now),
      isTrue,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.important, medium, now: now),
      isFalse,
    );
    expect(
      filter.matchesSmartView(SmartTaskView.important, completed, now: now),
      isFalse,
    );
  });

  test('searches notes, location, and tags case-insensitively', () {
    final task = CloudTask(
      uid: 'searchable',
      summary: 'Repair shelf',
      description: 'Bring the drill',
      location: 'Workshop',
      categories: const <String>['Home', 'Tools'],
    );

    expect(filter.matchesQuery(task, 'DRILL'), isTrue);
    expect(filter.matchesQuery(task, 'workshop'), isTrue);
    expect(filter.matchesQuery(task, 'tool'), isTrue);
    expect(filter.matchesTag(task, 'Home'), isTrue);
    expect(filter.matchesQuery(task, 'groceries'), isFalse);
  });
}

CloudTask _task(
  String summary, {
  DateTime? due,
  DateTime? start,
  CloudTaskStatus? status,
  int? priority,
}) {
  return CloudTask(
    uid: summary.toLowerCase().replaceAll(' ', '-'),
    summary: summary,
    status: status,
    priority: priority,
    start: start == null ? null : CloudTaskDate(value: start, isAllDay: false),
    due: due == null ? null : CloudTaskDate(value: due, isAllDay: false),
  );
}
