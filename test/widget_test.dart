import 'package:cloud_tasks/src/account/account_store.dart';
import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_app.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_controller.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_preferences.dart';
import 'package:cloud_tasks/src/data/sqlite_task_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the privacy-preserving Nextcloud connection screen', (
    tester,
  ) async {
    final controller = CloudTasksController(
      accountStore: _EmptyAccountStore(),
      taskStore: _WidgetTestTaskStore(),
      browserLauncher: (_) async => true,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(CloudTasksApp(controller: controller));
    await tester.pump();

    expect(find.text('Cloud Tasks'), findsOneWidget);
    expect(find.text('Connect to Nextcloud'), findsOneWidget);
    expect(find.text('Nextcloud server'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('opens and dismisses device settings while signed out', (
    tester,
  ) async {
    final controller = CloudTasksController(
      accountStore: _EmptyAccountStore(),
      taskStore: _WidgetTestTaskStore(),
      browserLauncher: (_) async => true,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(CloudTasksApp(controller: controller));
    await tester.pump();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Automatic sync'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _WidgetTestTaskStore extends SqliteTaskStore {
  @override
  Future<CloudTasksPreferences> readAppPreferences() async {
    return const CloudTasksPreferences();
  }

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
