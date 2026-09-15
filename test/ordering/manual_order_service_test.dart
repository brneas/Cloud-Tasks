import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/ordering/manual_order_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ManualOrderService();

  group('ManualOrderService', () {
    test('sorts by synchronized X-APPLE-SORT-ORDER', () {
      const tasks = <CloudTask>[
        CloudTask(uid: 'third', summary: 'Third', sortOrder: 300),
        CloudTask(uid: 'first', summary: 'First', sortOrder: 100),
        CloudTask(uid: 'second', summary: 'Second', sortOrder: 200),
      ];

      expect(service.sort(tasks).map((task) => task.uid), <String>[
        'first',
        'second',
        'third',
      ]);
    });

    test('keeps tasks without a server order deterministic and last', () {
      const tasks = <CloudTask>[
        CloudTask(uid: 'z', summary: 'No order'),
        CloudTask(uid: 'a', summary: 'No order'),
        CloudTask(uid: 'ordered', summary: 'Ordered', sortOrder: 5),
      ];

      expect(service.sort(tasks).map((task) => task.uid), <String>[
        'ordered',
        'a',
        'z',
      ]);
    });

    test('allocates sparse positions without rewriting siblings', () {
      expect(service.positionBetween(previous: 100, next: 200), 150);
      expect(service.positionBetween(previous: 100, next: 101), isNull);
    });

    test('reorders by changing only the moved task when a gap exists', () {
      const tasks = <CloudTask>[
        CloudTask(uid: 'a', summary: 'A', sortOrder: 1048576),
        CloudTask(uid: 'b', summary: 'B', sortOrder: 2097152),
        CloudTask(uid: 'c', summary: 'C', sortOrder: 3145728),
      ];

      final reordered = service.reorder(tasks, 0, 2);

      expect(reordered.map((task) => task.uid), <String>['b', 'a', 'c']);
      expect(reordered.map((task) => task.sortOrder), <int>[
        ManualOrderService.spacing * 2,
        ManualOrderService.spacing * 2 + ManualOrderService.spacing ~/ 2,
        ManualOrderService.spacing * 3,
      ]);
    });

    test('reindexes a sibling group only when no integer gap remains', () {
      const tasks = <CloudTask>[
        CloudTask(uid: 'a', summary: 'A', sortOrder: 10),
        CloudTask(uid: 'b', summary: 'B', sortOrder: 11),
        CloudTask(uid: 'c', summary: 'C', sortOrder: 12),
      ];

      final reordered = service.reorder(tasks, 2, 1);

      expect(reordered.map((task) => task.uid), <String>['a', 'c', 'b']);
      expect(reordered.map((task) => task.sortOrder), <int>[
        ManualOrderService.spacing,
        ManualOrderService.spacing * 2,
        ManualOrderService.spacing * 3,
      ]);
    });

    test('converts a descending drag back to ascending server order', () {
      const displayed = <CloudTask>[
        CloudTask(uid: 'c', summary: 'C', sortOrder: 300),
        CloudTask(uid: 'b', summary: 'B', sortOrder: 200),
        CloudTask(uid: 'a', summary: 'A', sortOrder: 100),
      ];

      final ascending = service.reorderDisplayed(
        displayed,
        0,
        2,
        descending: true,
      );

      expect(ascending.map((task) => task.uid), <String>['a', 'c', 'b']);
      expect(
        service.sort(ascending, descending: true).map((task) => task.uid),
        <String>['b', 'c', 'a'],
      );
    });

    test('normalizes ambiguous positions in the requested display order', () {
      const displayed = <CloudTask>[
        CloudTask(uid: 'c', summary: 'C', sortOrder: 300),
        CloudTask(uid: 'a', summary: 'A'),
        CloudTask(uid: 'b', summary: 'B'),
      ];

      final ascending = service.reorderDisplayed(
        displayed,
        2,
        1,
        descending: true,
      );

      expect(
        service.sort(ascending, descending: true).map((task) => task.uid),
        <String>['c', 'b', 'a'],
      );
      expect(ascending.map((task) => task.sortOrder), <int>[
        ManualOrderService.spacing,
        ManualOrderService.spacing * 2,
        ManualOrderService.spacing * 3,
      ]);
    });

    test(
      'reorders active tasks without colliding with hidden completed tasks',
      () {
        const siblings = <CloudTask>[
          CloudTask(uid: 'a', summary: 'A', sortOrder: 1048576),
          CloudTask(
            uid: 'done',
            summary: 'Done',
            sortOrder: 2097152,
            status: CloudTaskStatus.completed,
          ),
          CloudTask(uid: 'b', summary: 'B', sortOrder: 3145728),
        ];

        final reordered = service.reorderDisplayedSubset(
          siblings,
          const <String>['a', 'b'],
          1,
          0,
          descending: false,
        );

        expect(reordered.map((task) => task.uid), <String>['b', 'done', 'a']);
        expect(
          reordered.map((task) => task.sortOrder).toSet().length,
          siblings.length,
        );
        expect(
          reordered.singleWhere((task) => task.uid == 'done').sortOrder,
          ManualOrderService.spacing * 2,
        );
      },
    );

    test('preserves hidden sibling slots in descending display order', () {
      const siblings = <CloudTask>[
        CloudTask(uid: 'a', summary: 'A', sortOrder: 1048576),
        CloudTask(
          uid: 'done',
          summary: 'Done',
          sortOrder: 2097152,
          status: CloudTaskStatus.completed,
        ),
        CloudTask(uid: 'b', summary: 'B', sortOrder: 3145728),
      ];

      final reordered = service.reorderDisplayedSubset(
        siblings,
        const <String>['b', 'a'],
        1,
        0,
        descending: true,
      );

      expect(
        service.sort(reordered, descending: true).map((task) => task.uid),
        <String>['a', 'done', 'b'],
      );
      expect(
        reordered.map((task) => task.sortOrder).toSet().length,
        siblings.length,
      );
    });

    test('normalizes an ambiguous group when reordering a visible subset', () {
      const siblings = <CloudTask>[
        CloudTask(uid: 'a', summary: 'A', sortOrder: 100),
        CloudTask(
          uid: 'done',
          summary: 'Done',
          sortOrder: 100,
          status: CloudTaskStatus.completed,
        ),
        CloudTask(uid: 'b', summary: 'B'),
      ];

      final reordered = service.reorderDisplayedSubset(
        siblings,
        const <String>['a', 'b'],
        1,
        0,
        descending: false,
      );

      expect(reordered.map((task) => task.uid), <String>['b', 'done', 'a']);
      expect(reordered.map((task) => task.sortOrder), <int>[
        ManualOrderService.spacing,
        ManualOrderService.spacing * 2,
        ManualOrderService.spacing * 3,
      ]);
    });

    test('inserts new tasks at the top of either visible direction', () {
      const ascending = <CloudTask>[
        CloudTask(uid: 'a', summary: 'A', sortOrder: 2097152),
        CloudTask(uid: 'b', summary: 'B', sortOrder: 3145728),
      ];
      const newTask = CloudTask(uid: 'new', summary: 'New');

      final ascendingResult = service.insertDisplayed(
        ascending,
        newTask,
        descending: false,
      );
      final descendingResult = service.insertDisplayed(
        ascending.reversed.toList(),
        newTask,
        descending: true,
      );

      expect(service.sort(ascendingResult).map((task) => task.uid), <String>[
        'new',
        'a',
        'b',
      ]);
      expect(
        service
            .sort(descendingResult, descending: true)
            .map((task) => task.uid),
        <String>['new', 'b', 'a'],
      );
    });
  });
}
