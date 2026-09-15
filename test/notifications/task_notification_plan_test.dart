import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/notifications/task_notification_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = TaskNotificationPlanner();

  test('plans every future display alarm against its own anchor', () {
    final task = CloudTask(
      uid: 'scheduled',
      summary: 'Bring tools',
      calendarId: 'personal',
      start: CloudTaskDate(value: DateTime(2030, 5, 4, 9), isAllDay: false),
      due: CloudTaskDate(value: DateTime(2030, 5, 4, 17), isAllDay: false),
      reminders: const <CloudTaskReminder>[
        CloudTaskReminder(trigger: '-PT15M', relatedToEnd: false),
        CloudTaskReminder(trigger: '-PT1H', relatedToEnd: true),
      ],
    );

    final plan = planner.build(<CloudTask>[task], now: DateTime(2030, 5, 1));

    expect(plan, hasLength(2));
    expect(plan.first.scheduledAt, DateTime(2030, 5, 4, 8, 45));
    expect(plan.last.scheduledAt, DateTime(2030, 5, 4, 16));
    expect(plan.map((item) => item.id).toSet(), hasLength(2));
  });

  test('ignores expired, completed, and non-display alarms', () {
    final tasks = <CloudTask>[
      CloudTask(
        uid: 'expired',
        summary: 'Expired',
        due: CloudTaskDate(value: DateTime(2029, 1, 1), isAllDay: true),
        reminders: const <CloudTaskReminder>[
          CloudTaskReminder(trigger: 'PT0S', relatedToEnd: true),
        ],
      ),
      CloudTask(
        uid: 'completed',
        summary: 'Completed',
        status: CloudTaskStatus.completed,
        due: CloudTaskDate(value: DateTime(2031, 1, 1), isAllDay: true),
        reminders: const <CloudTaskReminder>[
          CloudTaskReminder(trigger: 'PT0S', relatedToEnd: true),
        ],
      ),
      CloudTask(
        uid: 'completed-timestamp',
        summary: 'Completed timestamp',
        completedAt: DateTime.utc(2030, 1, 1),
        due: CloudTaskDate(value: DateTime(2031, 1, 1), isAllDay: true),
        reminders: const <CloudTaskReminder>[
          CloudTaskReminder(trigger: 'PT0S', relatedToEnd: true),
        ],
      ),
      CloudTask(
        uid: 'email',
        summary: 'Email alarm',
        due: CloudTaskDate(value: DateTime(2031, 1, 1), isAllDay: true),
        reminders: const <CloudTaskReminder>[
          CloudTaskReminder(
            trigger: 'PT0S',
            relatedToEnd: true,
            action: 'EMAIL',
          ),
        ],
      ),
    ];

    expect(planner.build(tasks, now: DateTime(2030, 1, 1)), isEmpty);
  });

  test('uses a stable id for the same synchronized alarm', () {
    const key = 'calendar\ntask\n0\ntrue\n-PT1H';
    expect(TaskNotificationPlanner.stableId(key), 110128238);
    expect(
      TaskNotificationPlanner.stableId(key),
      TaskNotificationPlanner.stableId(key),
    );
  });

  test('resolves a server TZID before scheduling on this device', () {
    final task = CloudTask(
      uid: 'zoned',
      summary: 'Zoned task',
      start: CloudTaskDate(
        value: DateTime(2030, 5, 4, 9),
        isAllDay: false,
        timeZoneId: 'America/New_York',
      ),
      reminders: const <CloudTaskReminder>[
        CloudTaskReminder(trigger: 'PT0S', relatedToEnd: false),
      ],
    );

    final scheduled = planner.resolve(task, task.reminders.single);

    expect(scheduled?.toUtc(), DateTime.utc(2030, 5, 4, 13));
  });

  test('schedules an absolute UTC alarm without a task date', () {
    final task = CloudTask(
      uid: 'absolute',
      summary: 'Independent reminder',
      reminders: const <CloudTaskReminder>[
        CloudTaskReminder(trigger: '20300504T130000Z', relatedToEnd: false),
      ],
    );

    final plan = planner.build(<CloudTask>[
      task,
    ], now: DateTime.utc(2030, 5, 1));

    expect(plan, hasLength(1));
    expect(plan.single.scheduledAt.toUtc(), DateTime.utc(2030, 5, 4, 13));
  });
}
