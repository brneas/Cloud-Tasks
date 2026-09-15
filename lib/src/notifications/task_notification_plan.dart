import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

class TaskNotificationPlan {
  const TaskNotificationPlan({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledAt,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime scheduledAt;
  final String payload;
}

class TaskNotificationPlanner {
  const TaskNotificationPlanner();

  static bool _timeZonesInitialized = false;

  List<TaskNotificationPlan> build(
    Iterable<CloudTask> tasks, {
    required DateTime now,
  }) {
    final desired = <int, TaskNotificationPlan>{};
    for (final task in tasks) {
      if (task.isClosed) {
        continue;
      }
      for (var index = 0; index < task.reminders.length; index++) {
        final reminder = task.reminders[index];
        if (reminder.action.toUpperCase() != 'DISPLAY') {
          continue;
        }
        final scheduledAt = resolve(task, reminder);
        if (scheduledAt == null || !scheduledAt.isAfter(now)) {
          continue;
        }
        final key =
            '${task.calendarId ?? ''}\n${task.uid}\n$index\n'
            '${reminder.relatedToEnd}\n${reminder.trigger}';
        final id = stableId(key);
        desired[id] = TaskNotificationPlan(
          id: id,
          title: task.summary.isEmpty ? 'Task reminder' : task.summary,
          body:
              reminder.description ??
              (reminder.relatedToEnd
                  ? 'This task is due soon.'
                  : 'This task starts soon.'),
          scheduledAt: scheduledAt,
          payload: '${task.calendarId ?? ''}\n${task.uid}',
        );
      }
    }
    return List<TaskNotificationPlan>.unmodifiable(desired.values);
  }

  DateTime? resolve(CloudTask task, CloudTaskReminder reminder) {
    final duration = _parseDuration(reminder.trigger);
    if (duration != null) {
      final date = reminder.relatedToEnd ? task.due : task.start;
      if (date == null) {
        return null;
      }
      return _localAnchor(date).add(duration);
    }
    return _parseDateTime(reminder.trigger);
  }

  static int stableId(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  static DateTime _localAnchor(CloudTaskDate date) {
    var value = date.value.isUtc ? date.value.toLocal() : date.value;
    final timeZoneId = date.timeZoneId;
    if (!date.isAllDay && timeZoneId != null && timeZoneId.isNotEmpty) {
      if (!_timeZonesInitialized) {
        time_zone_data.initializeTimeZones();
        _timeZonesInitialized = true;
      }
      try {
        value = time_zone.TZDateTime(
          time_zone.getLocation(timeZoneId),
          value.year,
          value.month,
          value.day,
          value.hour,
          value.minute,
          value.second,
        ).toLocal();
      } on Object {
        // Preserve floating-time behavior for a private or unknown TZID.
      }
    }
    if (!date.isAllDay) {
      return value;
    }
    // RFC date values have no time. Nine in the morning avoids a surprising
    // midnight notification while keeping the reminder on the selected day.
    return DateTime(value.year, value.month, value.day, 9);
  }

  static Duration? _parseDuration(String source) {
    final match = RegExp(
      r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
      caseSensitive: false,
    ).firstMatch(source.trim());
    if (match == null) {
      return null;
    }
    final sign = match.group(1) == '-' ? -1 : 1;
    int part(int index) => int.tryParse(match.group(index) ?? '') ?? 0;
    final duration = Duration(
      days: part(2) * 7 + part(3),
      hours: part(4),
      minutes: part(5),
      seconds: part(6),
    );
    return duration * sign;
  }

  static DateTime? _parseDateTime(String source) {
    final value = source.trim();
    if (value.length < 15 || value[8] != 'T') {
      return null;
    }
    try {
      final parts = <int>[
        int.parse(value.substring(0, 4)),
        int.parse(value.substring(4, 6)),
        int.parse(value.substring(6, 8)),
        int.parse(value.substring(9, 11)),
        int.parse(value.substring(11, 13)),
        int.parse(value.substring(13, 15)),
      ];
      return value.endsWith('Z')
          ? DateTime.utc(
              parts[0],
              parts[1],
              parts[2],
              parts[3],
              parts[4],
              parts[5],
            ).toLocal()
          : DateTime(
              parts[0],
              parts[1],
              parts[2],
              parts[3],
              parts[4],
              parts[5],
            );
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }
}
