import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:rrule/rrule.dart';

class RecurringTaskAdvance {
  const RecurringTaskAdvance({
    required this.start,
    required this.due,
    required this.recurrenceRule,
  });

  final CloudTaskDate? start;
  final CloudTaskDate? due;
  final String recurrenceRule;
}

class TaskRecurrenceService {
  const TaskRecurrenceService();

  RecurringTaskAdvance? nextOccurrence(CloudTask task) {
    final source = task.recurrenceRule;
    final anchor = task.due ?? task.start;
    if (source == null || anchor == null) {
      return null;
    }
    final nextRule = _decrementCount(source);
    if (nextRule == null) {
      return null;
    }

    try {
      final rule = RecurrenceRule.fromString(
        source.startsWith('RRULE:') ? source : 'RRULE:$source',
      );
      final anchorValue = _asRuleDate(anchor.value);
      DateTime? next;
      for (final instance in rule.getInstances(start: anchorValue)) {
        if (instance.isAfter(anchorValue)) {
          next = instance;
          break;
        }
      }
      if (next == null) {
        return null;
      }
      final wallTimeDelta = next.difference(anchorValue);
      return RecurringTaskAdvance(
        start: _shift(task.start, wallTimeDelta),
        due: _shift(task.due, wallTimeDelta),
        recurrenceRule: nextRule,
      );
    } on Object {
      // Allow normal completion rather than risking an incorrectly generated
      // occurrence from a rule this client cannot evaluate.
      return null;
    }
  }

  static DateTime _asRuleDate(DateTime value) => DateTime.utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
  );

  static CloudTaskDate? _shift(CloudTaskDate? source, Duration delta) {
    if (source == null) {
      return null;
    }
    final shifted = _asRuleDate(source.value).add(delta);
    final value = source.value.isUtc
        ? DateTime.utc(
            shifted.year,
            shifted.month,
            shifted.day,
            shifted.hour,
            shifted.minute,
            shifted.second,
          )
        : DateTime(
            shifted.year,
            shifted.month,
            shifted.day,
            shifted.hour,
            shifted.minute,
            shifted.second,
          );
    return CloudTaskDate(
      value: value,
      isAllDay: source.isAllDay,
      timeZoneId: source.timeZoneId,
    );
  }

  static String? _decrementCount(String source) {
    final prefix = source.startsWith('RRULE:') ? 'RRULE:' : '';
    final parts = source.substring(prefix.length).split(';');
    for (var index = 0; index < parts.length; index++) {
      if (!parts[index].toUpperCase().startsWith('COUNT=')) {
        continue;
      }
      final count = int.tryParse(parts[index].substring(6));
      if (count == null || count <= 1) {
        return null;
      }
      parts[index] = 'COUNT=${count - 1}';
      break;
    }
    return parts.join(';');
  }
}
