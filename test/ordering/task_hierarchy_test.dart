import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/ordering/task_hierarchy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hierarchy = TaskHierarchy();

  test('builds and orders every sibling group independently', () {
    const tasks = <CloudTask>[
      CloudTask(uid: 'root-b', summary: 'Root B', sortOrder: 20),
      CloudTask(
        uid: 'child-b',
        summary: 'Child B',
        parentUid: 'root-a',
        sortOrder: 20,
      ),
      CloudTask(uid: 'root-a', summary: 'Root A', sortOrder: 10),
      CloudTask(
        uid: 'child-a',
        summary: 'Child A',
        parentUid: 'root-a',
        sortOrder: 10,
      ),
      CloudTask(
        uid: 'grandchild',
        summary: 'Grandchild',
        parentUid: 'child-a',
        sortOrder: 10,
      ),
    ];

    final roots = hierarchy.build(tasks, descending: false);

    expect(roots.map((node) => node.task.uid), <String>['root-a', 'root-b']);
    expect(roots.first.children.map((node) => node.task.uid), <String>[
      'child-a',
      'child-b',
    ]);
    expect(roots.first.children.first.children.single.task.uid, 'grandchild');

    final descending = hierarchy.build(tasks, descending: true);
    expect(
      descending
          .firstWhere((node) => node.task.uid == 'root-a')
          .children
          .map((node) => node.task.uid),
      <String>['child-b', 'child-a'],
    );
  });

  test('promotes orphans and cycles instead of hiding tasks', () {
    const tasks = <CloudTask>[
      CloudTask(uid: 'orphan', summary: 'Orphan', parentUid: 'missing'),
      CloudTask(uid: 'cycle-a', summary: 'Cycle A', parentUid: 'cycle-b'),
      CloudTask(uid: 'cycle-b', summary: 'Cycle B', parentUid: 'cycle-a'),
      CloudTask(uid: 'self', summary: 'Self', parentUid: 'self'),
    ];

    final roots = hierarchy.build(tasks, descending: false);
    final seen = <String>[];
    void visit(TaskHierarchyNode node) {
      seen.add(node.task.uid);
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final root in roots) {
      visit(root);
    }

    expect(seen.toSet(), <String>{'orphan', 'cycle-a', 'cycle-b', 'self'});
    expect(seen, hasLength(4));
  });

  test('finds all descendants without looping through a bad cycle', () {
    const tasks = <CloudTask>[
      CloudTask(uid: 'root', summary: 'Root'),
      CloudTask(uid: 'child', summary: 'Child', parentUid: 'root'),
      CloudTask(uid: 'grandchild', summary: 'Grandchild', parentUid: 'child'),
      CloudTask(uid: 'cycle', summary: 'Cycle', parentUid: 'cycle'),
    ];

    expect(hierarchy.descendantUids(tasks, 'root'), <String>{
      'child',
      'grandchild',
    });
    expect(hierarchy.descendantUids(tasks, 'cycle'), isEmpty);
  });
}
