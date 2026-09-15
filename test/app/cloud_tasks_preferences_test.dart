import 'package:cloud_tasks/src/app/cloud_tasks_preferences.dart';
import 'package:cloud_tasks/src/domain/task_view_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith keeps durable view state while changing settings', () {
    const original = CloudTasksPreferences(
      theme: CloudTasksTheme.dark,
      descendingManualOrder: true,
      lastCalendarId: 'personal',
      lastSmartView: SmartTaskView.today,
    );

    final changed = original.copyWith(automaticSyncMinutes: 30);

    expect(changed.theme, CloudTasksTheme.dark);
    expect(changed.automaticSyncMinutes, 30);
    expect(changed.descendingManualOrder, isTrue);
    expect(changed.lastCalendarId, 'personal');
    expect(changed.lastSmartView, SmartTaskView.today);
  });

  test(
    'copyWith can clear remembered navigation without resetting sorting',
    () {
      const original = CloudTasksPreferences(
        descendingManualOrder: true,
        lastCalendarId: 'personal',
        lastSmartView: SmartTaskView.completed,
      );

      final cleared = original.copyWith(
        clearLastCalendarId: true,
        clearLastSmartView: true,
      );

      expect(cleared.descendingManualOrder, isTrue);
      expect(cleared.lastCalendarId, isNull);
      expect(cleared.lastSmartView, isNull);
    },
  );
}
