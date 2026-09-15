import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/notifications/task_notification_plan.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

abstract interface class TaskNotificationScheduler {
  Future<void> reconcile(Iterable<CloudTask> tasks);

  Future<void> cancelAll();
}

class NoopTaskNotificationScheduler implements TaskNotificationScheduler {
  const NoopTaskNotificationScheduler();

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> reconcile(Iterable<CloudTask> tasks) async {}
}

class AndroidTaskNotificationScheduler implements TaskNotificationScheduler {
  AndroidTaskNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'cloud_tasks_reminders';
  static const _channelName = 'Task reminders';
  static const _channelDescription =
      'Reminders synchronized from Nextcloud task alarms';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _permissionRequested = false;
  static const _planner = TaskNotificationPlanner();

  Future<void> _initialize() async {
    if (_initialized) {
      return;
    }
    time_zone_data.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> reconcile(Iterable<CloudTask> tasks) async {
    await _initialize();
    final desired = <int, TaskNotificationPlan>{
      for (final notification in _planner.build(tasks, now: DateTime.now()))
        notification.id: notification,
    };

    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (!desired.containsKey(notification.id)) {
        await _plugin.cancel(notification.id);
      }
    }
    if (desired.isEmpty) {
      return;
    }
    if (!_permissionRequested) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _permissionRequested = true;
    }
    final pendingIds = pending.map((item) => item.id).toSet();
    for (final notification in desired.values) {
      if (pendingIds.contains(notification.id)) {
        await _plugin.cancel(notification.id);
      }
      await _plugin.zonedSchedule(
        notification.id,
        notification.title,
        notification.body,
        time_zone.TZDateTime.from(
          notification.scheduledAt.toUtc(),
          time_zone.UTC,
        ),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: notification.payload,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    await _initialize();
    await _plugin.cancelAll();
  }

}
