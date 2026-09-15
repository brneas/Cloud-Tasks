import 'package:cloud_tasks/src/account/account_store.dart';
import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_controller.dart';
import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/data/sqlite_task_store.dart';
import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/ordering/task_hierarchy.dart';
import 'package:cloud_tasks/src/widgets/cloud_task_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('restores every completed task from the collapsed section', (
    tester,
  ) async {
    final controller = _CompletedSectionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CloudTaskListView(controller: controller)),
      ),
    );

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('2 tasks'), findsOneWidget);
    expect(find.text('Restore all'), findsOneWidget);

    await tester.tap(find.text('Restore all'));
    await tester.pump();

    expect(controller.restoreCalls, 1);
    expect(find.text('2 completed tasks were restored.'), findsOneWidget);
  });
}

class _CompletedSectionController extends CloudTasksController {
  _CompletedSectionController()
      : super(
          accountStore: _EmptyAccountStore(),
          taskStore: _WidgetTaskStore(),
          browserLauncher: (_) async => true,
        );

  static final TaskCalendar _calendar = TaskCalendar(
    id: 'personal',
    accountId: 'account',
    href: Uri.parse('https://cloud.example/calendars/alice/personal/'),
    displayName: 'Personal',
    isReadOnly: false,
  );

  int restoreCalls = 0;

  @override
  TaskCalendar? get selectedCalendar => _calendar;

  @override
  TaskCalendar? get taskCreationCalendar => null;

  @override
  String? get selectedCalendarId => _calendar.id;

  @override
  bool get isSmartView => false;

  @override
  String get viewTitle => _calendar.displayName;

  @override
  String get viewSubtitle => 'Nextcloud list';

  @override
  bool get canRestoreCompletedTasks => true;

  @override
  List<TaskHierarchyNode> get taskTree => const <TaskHierarchyNode>[
        TaskHierarchyNode(
          task: CloudTask(
            uid: 'done-1',
            calendarId: 'personal',
            summary: 'Done one',
            status: CloudTaskStatus.completed,
          ),
          children: <TaskHierarchyNode>[],
        ),
        TaskHierarchyNode(
          task: CloudTask(
            uid: 'done-2',
            calendarId: 'personal',
            summary: 'Done two',
            status: CloudTaskStatus.completed,
          ),
          children: <TaskHierarchyNode>[],
        ),
      ];

  @override
  Future<int> restoreCompletedTasks() async {
    restoreCalls++;
    return 2;
  }
}

class _WidgetTaskStore extends SqliteTaskStore {
  @override
  Future<void> close() async {}
}

class _EmptyAccountStore implements AccountStore {
  @override
  Future<void> delete(String accountId) async {}

  @override
  Future<List<NextcloudAccount>> readAll() async {
    return const <NextcloudAccount>[];
  }

  @override
  Future<void> save(NextcloudAccount account) async {}
}
