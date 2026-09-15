import 'package:cloud_tasks/src/domain/cloud_task.dart';

class ManualOrderService {
  const ManualOrderService();

  static const int spacing = 1048576;

  List<CloudTask> sort(
    Iterable<CloudTask> tasks, {
    bool descending = false,
  }) {
    final result = List<CloudTask>.of(tasks);
    result.sort((left, right) {
      final leftOrder = left.sortOrder;
      final rightOrder = right.sortOrder;

      if (leftOrder == null && rightOrder == null) {
        return left.uid.compareTo(right.uid);
      }
      if (leftOrder == null) {
        return 1;
      }
      if (rightOrder == null) {
        return -1;
      }

      final comparison = leftOrder.compareTo(rightOrder);
      if (comparison == 0) {
        return left.uid.compareTo(right.uid);
      }
      return descending ? -comparison : comparison;
    });
    return List<CloudTask>.unmodifiable(result);
  }

  /// Returns a sparse position between two visible siblings.
  ///
  /// A null result means there is no integer gap and the sibling group should
  /// be reindexed before retrying.
  int? positionBetween({
    required int? previous,
    required int? next,
  }) {
    if (previous == null && next == null) {
      return spacing;
    }
    if (previous == null) {
      return next! > spacing ? next - spacing : null;
    }
    if (next == null) {
      return previous + spacing;
    }
    if (next <= previous + 1) {
      return null;
    }
    return previous + ((next - previous) ~/ 2);
  }

  List<CloudTask> reindex(Iterable<CloudTask> tasks) {
    var position = spacing;
    final result = <CloudTask>[];
    for (final task in tasks) {
      result.add(task.copyWith(sortOrder: position));
      position += spacing;
    }
    return List<CloudTask>.unmodifiable(result);
  }

  /// Applies a drag in either display direction and returns ascending order.
  ///
  /// Missing or duplicate positions cannot represent an exact reversible
  /// order. The first drag in such a list assigns every sibling a unique sparse
  /// position while preserving the requested visible order.
  List<CloudTask> reorderDisplayed(
    List<CloudTask> visibleSiblings,
    int oldIndex,
    int newIndex, {
    required bool descending,
  }) {
    if (oldIndex < 0 || oldIndex >= visibleSiblings.length) {
      throw RangeError.index(oldIndex, visibleSiblings, 'oldIndex');
    }
    if (newIndex < 0 || newIndex > visibleSiblings.length) {
      throw RangeError.range(
        newIndex,
        0,
        visibleSiblings.length,
        'newIndex',
      );
    }

    final desiredDisplay = List<CloudTask>.of(visibleSiblings);
    final moved = desiredDisplay.removeAt(oldIndex);
    var insertionIndex = newIndex;
    if (insertionIndex > oldIndex) {
      insertionIndex--;
    }
    desiredDisplay.insert(insertionIndex, moved);
    if (_sameUidOrder(visibleSiblings, desiredDisplay)) {
      return sort(visibleSiblings);
    }

    final desiredAscending = descending
        ? desiredDisplay.reversed.toList(growable: false)
        : desiredDisplay;
    final currentAscending = sort(visibleSiblings);
    if (!_hasUniqueManualOrder(currentAscending)) {
      return reindex(desiredAscending);
    }

    final oldAscendingIndex = currentAscending.indexWhere(
      (task) => task.uid == moved.uid,
    );
    final desiredAscendingIndex = desiredAscending.indexWhere(
      (task) => task.uid == moved.uid,
    );
    final serviceNewIndex = desiredAscendingIndex > oldAscendingIndex
        ? desiredAscendingIndex + 1
        : desiredAscendingIndex;
    return reorder(
      currentAscending,
      oldAscendingIndex,
      serviceNewIndex,
    );
  }

  /// Reorders a visible subset without losing the positions of hidden siblings.
  ///
  /// This is used when completed tasks are collapsed below active tasks. Valid
  /// hidden positions remain untouched: reordered tasks exchange the existing
  /// visible position slots. An ambiguous group is reindexed only when its
  /// missing or duplicate positions cannot represent that safely.
  List<CloudTask> reorderDisplayedSubset(
    List<CloudTask> allSiblings,
    List<String> displayedUids,
    int oldIndex,
    int newIndex, {
    required bool descending,
  }) {
    final allByUid = <String, CloudTask>{
      for (final task in allSiblings) task.uid: task,
    };
    final visible = <CloudTask>[];
    for (final uid in displayedUids) {
      final task = allByUid[uid];
      if (task == null) {
        throw ArgumentError.value(
          uid,
          'displayedUids',
          'Every displayed task must be a sibling.',
        );
      }
      visible.add(task);
    }
    if (visible.length != displayedUids.toSet().length) {
      throw ArgumentError.value(
        displayedUids,
        'displayedUids',
        'Displayed task UIDs must be unique.',
      );
    }

    final reorderedVisible = reorderDisplayed(
      visible,
      oldIndex,
      newIndex,
      descending: descending,
    );
    final reorderedDisplay = descending
        ? reorderedVisible.reversed.toList(growable: false)
        : reorderedVisible;
    if (_sameUidOrder(visible, reorderedDisplay)) {
      return sort(allSiblings);
    }
    if (visible.length == allSiblings.length) {
      return reorderedVisible;
    }

    final visibleUids = displayedUids.toSet();
    var visibleIndex = 0;
    final fullAscending = sort(allSiblings);
    final fullDisplay = descending
        ? fullAscending.reversed.toList(growable: false)
        : fullAscending;
    final desiredFullDisplay = <CloudTask>[
      for (final task in fullDisplay)
        if (visibleUids.contains(task.uid))
          reorderedDisplay[visibleIndex++]
        else
          task,
    ];
    if (_hasUniqueManualOrder(fullAscending)) {
      final visibleSlots = fullAscending
          .where((task) => visibleUids.contains(task.uid))
          .map((task) => task.sortOrder!)
          .toList(growable: false);
      final desiredVisibleAscending = descending
          ? reorderedDisplay.reversed.toList(growable: false)
          : reorderedDisplay;
      final positionedVisible = <String, CloudTask>{};
      for (var index = 0; index < desiredVisibleAscending.length; index++) {
        final task = desiredVisibleAscending[index];
        positionedVisible[task.uid] = task.copyWith(
          sortOrder: visibleSlots[index],
        );
      }
      return sort(
        fullAscending.map((task) => positionedVisible[task.uid] ?? task),
      );
    }
    return reindex(
      descending ? desiredFullDisplay.reversed : desiredFullDisplay,
    );
  }

  /// Inserts a new task at a visible index and returns ascending server order.
  List<CloudTask> insertDisplayed(
    List<CloudTask> visibleSiblings,
    CloudTask newTask, {
    required bool descending,
    int visibleIndex = 0,
  }) {
    if (visibleIndex < 0 || visibleIndex > visibleSiblings.length) {
      throw RangeError.range(
        visibleIndex,
        0,
        visibleSiblings.length,
        'visibleIndex',
      );
    }
    final desiredDisplay = List<CloudTask>.of(visibleSiblings)
      ..insert(visibleIndex, newTask);
    final desiredAscending = descending
        ? desiredDisplay.reversed.toList(growable: false)
        : desiredDisplay;
    final currentAscending = sort(visibleSiblings);
    if (!_hasUniqueManualOrder(currentAscending)) {
      return reindex(desiredAscending);
    }

    final insertionIndex = desiredAscending.indexWhere(
      (task) => task.uid == newTask.uid,
    );
    final previous = insertionIndex == 0
        ? null
        : desiredAscending[insertionIndex - 1].sortOrder;
    final next = insertionIndex == desiredAscending.length - 1
        ? null
        : desiredAscending[insertionIndex + 1].sortOrder;
    final position = positionBetween(previous: previous, next: next);
    if (position == null) {
      return reindex(desiredAscending);
    }
    desiredAscending[insertionIndex] = newTask.copyWith(sortOrder: position);
    return List<CloudTask>.unmodifiable(desiredAscending);
  }

  /// Applies a visible drag operation and changes only the moved task when a
  /// sparse position is available. The group is reindexed only when needed.
  List<CloudTask> reorder(
    List<CloudTask> visibleSiblings,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= visibleSiblings.length) {
      throw RangeError.index(oldIndex, visibleSiblings, 'oldIndex');
    }
    if (newIndex < 0 || newIndex > visibleSiblings.length) {
      throw RangeError.range(
        newIndex,
        0,
        visibleSiblings.length,
        'newIndex',
      );
    }

    final reordered = List<CloudTask>.of(visibleSiblings);
    final moved = reordered.removeAt(oldIndex);
    var insertionIndex = newIndex;
    if (insertionIndex > oldIndex) {
      insertionIndex--;
    }
    reordered.insert(insertionIndex, moved);

    final previous = insertionIndex == 0
        ? null
        : reordered[insertionIndex - 1].sortOrder;
    final next = insertionIndex == reordered.length - 1
        ? null
        : reordered[insertionIndex + 1].sortOrder;
    final position = positionBetween(previous: previous, next: next);
    if (position == null) {
      return reindex(reordered);
    }

    reordered[insertionIndex] = moved.copyWith(sortOrder: position);
    return List<CloudTask>.unmodifiable(reordered);
  }

  static bool _hasUniqueManualOrder(List<CloudTask> tasks) {
    int? previous;
    for (final task in tasks) {
      final current = task.sortOrder;
      if (current == null || (previous != null && current <= previous)) {
        return false;
      }
      previous = current;
    }
    return true;
  }

  static bool _sameUidOrder(List<CloudTask> left, List<CloudTask> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index].uid != right[index].uid) {
        return false;
      }
    }
    return true;
  }
}
