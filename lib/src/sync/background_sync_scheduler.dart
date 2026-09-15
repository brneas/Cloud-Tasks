import 'package:workmanager/workmanager.dart';

const cloudTasksBackgroundTask = 'cloudTasks.sync';
const _cloudTasksUniqueWork = 'cloudTasks.periodicSync';

abstract interface class BackgroundSyncScheduler {
  Future<void> configure(int intervalMinutes);
}

class NoopBackgroundSyncScheduler implements BackgroundSyncScheduler {
  const NoopBackgroundSyncScheduler();

  @override
  Future<void> configure(int intervalMinutes) async {}
}

class WorkmanagerBackgroundSyncScheduler implements BackgroundSyncScheduler {
  const WorkmanagerBackgroundSyncScheduler();

  @override
  Future<void> configure(int intervalMinutes) async {
    final workmanager = Workmanager();
    await workmanager.cancelByUniqueName(_cloudTasksUniqueWork);
    if (intervalMinutes <= 0) return;
    await workmanager.registerPeriodicTask(
      _cloudTasksUniqueWork,
      cloudTasksBackgroundTask,
      frequency: Duration(minutes: intervalMinutes),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}
