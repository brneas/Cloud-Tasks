import 'package:cloud_tasks/src/account/account_store.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_app.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_controller.dart';
import 'package:cloud_tasks/src/data/sqlite_task_store.dart';
import 'package:cloud_tasks/src/sync/background_sync_scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void cloudTasksCallbackDispatcher() {
  Workmanager().executeTask((taskName, _inputData) async {
    if (taskName != cloudTasksBackgroundTask) return true;
    WidgetsFlutterBinding.ensureInitialized();
    final controller = CloudTasksController(
      accountStore: SecureAccountStore(),
      taskStore: SqliteTaskStore(),
      browserLauncher: (_url) async => false,
    );
    try {
      await controller.initialize();
      return controller.account == null ||
          controller.state == CloudTasksViewState.ready;
    } finally {
      await controller.close();
      controller.dispose();
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(cloudTasksCallbackDispatcher);
  runApp(const CloudTasksApp());
}
