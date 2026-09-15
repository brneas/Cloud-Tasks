import 'package:cloud_tasks/src/account/account_store.dart';
import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_controller.dart';
import 'package:cloud_tasks/src/data/sqlite_task_store.dart';
import 'package:cloud_tasks/src/widgets/cloud_task_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps Smart Views collapsed until requested', (tester) async {
    final controller = CloudTasksController(
      accountStore: _EmptyAccountStore(),
      taskStore: _NavigationTestTaskStore(),
      browserLauncher: (_) async => true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TaskCalendarNavigation(controller: controller)),
      ),
    );

    expect(find.text('MY LISTS'), findsOneWidget);
    expect(find.text('Smart Views'), findsOneWidget);
    expect(find.text('Important'), findsNothing);

    await tester.tap(find.text('Smart Views'));
    await tester.pump();

    expect(find.text('Important'), findsOneWidget);
  });
}

class _NavigationTestTaskStore extends SqliteTaskStore {
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
