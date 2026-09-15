import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:cloud_tasks/src/caldav/caldav_discovery_service.dart';
import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/caldav/caldav_task_reader.dart';
import 'package:cloud_tasks/src/data/sqlite_task_store.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:cloud_tasks/src/sync/sync_contracts.dart';

class InitialSyncService {
  const InitialSyncService({
    required CalDavDiscoveryService discovery,
    required CalDavTaskReader taskReader,
    required SqliteTaskStore store,
  }) : _discovery = discovery,
       _taskReader = taskReader,
       _store = store;

  final CalDavDiscoveryService _discovery;
  final CalDavTaskReader _taskReader;
  final SqliteTaskStore _store;

  Future<SyncResult> synchronize(NextcloudAccount account) async {
    final discovered = await _discovery.discover(account);
    final cached = <String, TaskCalendar>{
      for (final calendar in await _store.readCalendars(account.id))
        calendar.id: calendar,
    };
    await _store.replaceCalendarSnapshot(
      account.id,
      discovered.calendars.map(
        (calendar) => _withSyncToken(calendar, cached[calendar.id]?.syncToken),
      ),
    );

    final warnings = <String>[];
    var synchronizedTasks = 0;
    for (final calendar in discovered.calendars) {
      try {
        final savedToken = cached[calendar.id]?.syncToken;
        if (savedToken != null) {
          try {
            final delta = await _taskReader.readChanges(calendar, savedToken);
            await _store.saveServerRecords(
              delta.changed,
              deletedHrefs: delta.deletedHrefs,
              nextState: CalendarSyncState(
                calendarId: calendar.id,
                href: calendar.href,
                syncToken: delta.nextSyncToken,
              ),
            );
            synchronizedTasks += delta.changed.length;
            continue;
          } on InvalidCalDavSyncTokenException {
            // Tokens can expire after server maintenance. A complete query
            // restores a consistent snapshot and seeds the latest token.
          }
        }
        final records = await _taskReader.readAll(calendar);
        await _store.replaceInitialSnapshot(calendar, records);
        synchronizedTasks += records.length;
      } on CalDavTaskReadException catch (error) {
        warnings.add('${calendar.displayName}: $error');
        continue;
      } on DavHttpException catch (error) {
        warnings.add('${calendar.displayName}: ${error.message}');
        continue;
      } on Object catch (error) {
        warnings.add(
          '${calendar.displayName}: Could not read tasks '
          '(${error.runtimeType}).',
        );
        continue;
      }
    }

    return SyncResult(
      calendars: discovered.calendars,
      synchronizedTaskCount: synchronizedTasks,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static TaskCalendar _withSyncToken(TaskCalendar calendar, String? syncToken) {
    return TaskCalendar(
      id: calendar.id,
      accountId: calendar.accountId,
      href: calendar.href,
      displayName: calendar.displayName,
      isReadOnly: calendar.isReadOnly,
      color: calendar.color,
      sortOrder: calendar.sortOrder,
      syncToken: syncToken,
      ownerHref: calendar.ownerHref,
      isSharedWithMe: calendar.isSharedWithMe,
      canBeShared: calendar.canBeShared,
    );
  }
}

class SyncResult {
  const SyncResult({
    required this.calendars,
    required this.synchronizedTaskCount,
    required this.warnings,
  });

  final List<TaskCalendar> calendars;
  final int synchronizedTaskCount;
  final List<String> warnings;
}
