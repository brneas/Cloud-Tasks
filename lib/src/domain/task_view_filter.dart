import 'package:cloud_tasks/src/domain/cloud_task.dart';

enum SmartTaskView {
  all,
  important,
  current,
  today,
  nextSevenDays,
  upcoming,
  overdue,
  completed,
}

class TaskViewFilter {
  const TaskViewFilter();

  bool matchesSmartView(
    SmartTaskView? view,
    CloudTask task, {
    required DateTime now,
  }) {
    if (view == null || view == SmartTaskView.all) {
      return true;
    }
    final completed = task.isClosed;
    if (view == SmartTaskView.completed) {
      return completed;
    }
    if (completed) {
      return false;
    }
    final localNow = now.isUtc ? now.toLocal() : now;
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));
    final date = displayDate(task);
    return switch (view) {
      SmartTaskView.important =>
        task.priority != null && task.priority! >= 1 && task.priority! <= 4,
      SmartTaskView.current =>
        task.start == null ||
            localDate(task.start!).isBefore(localNow) ||
            (task.due != null && localDate(task.due!).isBefore(localNow)),
      SmartTaskView.today =>
        _dateBefore(task.start, tomorrow) || _dateBefore(task.due, tomorrow),
      SmartTaskView.nextSevenDays =>
        _dateBefore(task.start, nextWeek) || _dateBefore(task.due, nextWeek),
      SmartTaskView.upcoming => date != null && !date.isBefore(tomorrow),
      SmartTaskView.overdue =>
        task.due != null && localDate(task.due!).isBefore(today),
      SmartTaskView.completed || SmartTaskView.all => true,
    };
  }

  bool matchesQuery(CloudTask task, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return task.summary.toLowerCase().contains(normalized) ||
        (task.description ?? '').toLowerCase().contains(normalized) ||
        (task.location ?? '').toLowerCase().contains(normalized) ||
        task.categories.any(
          (category) => category.toLowerCase().contains(normalized),
        );
  }

  bool matchesTag(CloudTask task, String? tag) =>
      tag == null || task.categories.contains(tag);

  DateTime? displayDate(CloudTask task) {
    final date = task.due ?? task.start;
    return date == null ? null : localDate(date);
  }

  DateTime localDate(CloudTaskDate date) {
    final value = date.value.isUtc ? date.value.toLocal() : date.value;
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
  }

  bool _dateBefore(CloudTaskDate? date, DateTime limit) =>
      date != null && localDate(date).isBefore(limit);
}
