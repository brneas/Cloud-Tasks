import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/ordering/manual_order_service.dart';

class TaskHierarchyNode {
  const TaskHierarchyNode({
    required this.task,
    required this.children,
  });

  final CloudTask task;
  final List<TaskHierarchyNode> children;
}

/// Builds a lossless task tree from CalDAV parent relationships.
///
/// Orphans and malformed cycles are promoted to the root so a bad remote
/// relationship can never make a task disappear from the application.
class TaskHierarchy {
  const TaskHierarchy({
    ManualOrderService ordering = const ManualOrderService(),
  }) : _ordering = ordering;

  final ManualOrderService _ordering;

  List<TaskHierarchyNode> build(
    Iterable<CloudTask> source, {
    required bool descending,
  }) {
    final tasksByUid = <String, CloudTask>{
      for (final task in source) task.uid: task,
    };
    final childrenByParent = <String, List<CloudTask>>{};
    final rootCandidates = <CloudTask>[];

    for (final task in tasksByUid.values) {
      final parentUid = task.parentUid;
      if (parentUid == null ||
          parentUid == task.uid ||
          !tasksByUid.containsKey(parentUid)) {
        rootCandidates.add(task);
      } else {
        childrenByParent.putIfAbsent(parentUid, () => <CloudTask>[]).add(task);
      }
    }

    final visited = <String>{};
    TaskHierarchyNode? visit(CloudTask task) {
      if (!visited.add(task.uid)) {
        return null;
      }
      final children = <TaskHierarchyNode>[];
      final orderedChildren = _ordering.sort(
        childrenByParent[task.uid] ?? const <CloudTask>[],
        descending: descending,
      );
      for (final child in orderedChildren) {
        final node = visit(child);
        if (node != null) {
          children.add(node);
        }
      }
      return TaskHierarchyNode(
        task: task,
        children: List<TaskHierarchyNode>.unmodifiable(children),
      );
    }

    final roots = <TaskHierarchyNode>[];
    for (final task in _ordering.sort(
      rootCandidates,
      descending: descending,
    )) {
      final node = visit(task);
      if (node != null) {
        roots.add(node);
      }
    }

    // A pure parent cycle has no natural root. Promote one deterministic task
    // and let the visited set terminate the malformed loop.
    for (final task in _ordering.sort(
      tasksByUid.values,
      descending: descending,
    )) {
      final node = visit(task);
      if (node != null) {
        roots.add(node);
      }
    }
    return List<TaskHierarchyNode>.unmodifiable(roots);
  }

  Set<String> descendantUids(
    Iterable<CloudTask> source,
    String taskUid,
  ) {
    final childrenByParent = <String, List<String>>{};
    for (final task in source) {
      final parentUid = task.parentUid;
      if (parentUid != null && task.uid != parentUid) {
        childrenByParent.putIfAbsent(parentUid, () => <String>[]).add(task.uid);
      }
    }
    final descendants = <String>{};
    final pending = <String>[taskUid];
    while (pending.isNotEmpty) {
      final parent = pending.removeLast();
      for (final child in childrenByParent[parent] ?? const <String>[]) {
        if (child != taskUid && descendants.add(child)) {
          pending.add(child);
        }
      }
    }
    return Set<String>.unmodifiable(descendants);
  }
}
