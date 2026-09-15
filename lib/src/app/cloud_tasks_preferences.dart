import 'package:cloud_tasks/src/domain/task_view_filter.dart';

enum CloudTasksTheme { system, light, dark }

class CloudTasksPreferences {
  const CloudTasksPreferences({
    this.theme = CloudTasksTheme.system,
    this.automaticSyncMinutes = 0,
    this.syncOnResume = true,
    this.descendingManualOrder = false,
    this.lastCalendarId,
    this.lastSmartView,
  });

  final CloudTasksTheme theme;

  /// Zero disables periodic synchronization while the app is open.
  final int automaticSyncMinutes;
  final bool syncOnResume;

  /// Local presentation state only. Task positions remain synchronized through
  /// X-APPLE-SORT-ORDER regardless of which direction is displayed.
  final bool descendingManualOrder;
  final String? lastCalendarId;
  final SmartTaskView? lastSmartView;

  CloudTasksPreferences copyWith({
    CloudTasksTheme? theme,
    int? automaticSyncMinutes,
    bool? syncOnResume,
    bool? descendingManualOrder,
    String? lastCalendarId,
    SmartTaskView? lastSmartView,
    bool clearLastCalendarId = false,
    bool clearLastSmartView = false,
  }) {
    return CloudTasksPreferences(
      theme: theme ?? this.theme,
      automaticSyncMinutes: automaticSyncMinutes ?? this.automaticSyncMinutes,
      syncOnResume: syncOnResume ?? this.syncOnResume,
      descendingManualOrder:
          descendingManualOrder ?? this.descendingManualOrder,
      lastCalendarId: clearLastCalendarId
          ? null
          : lastCalendarId ?? this.lastCalendarId,
      lastSmartView: clearLastSmartView
          ? null
          : lastSmartView ?? this.lastSmartView,
    );
  }
}
