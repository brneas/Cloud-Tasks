import 'dart:io';

import 'package:cloud_tasks/src/app/cloud_tasks_preferences.dart';
import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/data/sqlite_task_store.dart';
import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/domain/task_view_filter.dart';
import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_codec.dart';
import 'package:cloud_tasks/src/sync/sync_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('caches tasks in manual order and keeps raw documents', () async {
    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final calendar = TaskCalendar(
      id: 'personal',
      accountId: 'account',
      href: Uri(
        scheme: 'https',
        host: 'cloud.example',
        path: '/calendars/alice/personal/',
      ),
      displayName: 'Personal',
      isReadOnly: false,
    );
    final later = _record('later', 200);
    final first = _record('first', 100);

    await store.replaceInitialSnapshot(calendar, <TaskRecord>[later, first]);
    final cached = await store.readAllTasks(calendar.id);

    expect(cached.map((record) => record.task.uid), <String>['first', 'later']);
    expect(cached.first.rawDocument.serialize(), contains('X-UNKNOWN:keep'));
    expect(cached.first.baseDocument?.serialize(), contains('UID:first'));
  });

  test('persists the default list and sharing capabilities', () async {
    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final calendar = TaskCalendar(
      id: 'shared',
      accountId: 'account',
      href: Uri.parse('https://cloud.example/calendars/alice/shared/'),
      displayName: 'Shared project',
      isReadOnly: false,
      ownerHref: 'https://cloud.example/principals/users/bob/',
      isSharedWithMe: true,
      canBeShared: false,
    );

    await store.saveCalendars(<TaskCalendar>[calendar]);
    await store.setDefaultCalendarId('account', calendar.id);

    final saved = (await store.readCalendars('account')).single;
    expect(saved.ownerHref, calendar.ownerHref);
    expect(saved.isSharedWithMe, isTrue);
    expect(saved.canBeShared, isFalse);
    expect(await store.readDefaultCalendarId('account'), 'shared');

    await store.clearAccount('account');
    expect(await store.readDefaultCalendarId('account'), isNull);
  });

  test('coalesces local edits and atomically completes the queued write',
      () async {
    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final calendar = TaskCalendar(
      id: 'personal',
      accountId: 'account',
      href: Uri.parse('https://cloud.example/calendars/alice/personal/'),
      displayName: 'Personal',
      isReadOnly: false,
    );
    final original = _record('task', 100);
    await store.replaceInitialSnapshot(calendar, <TaskRecord>[original]);

    final renamedDocument = const VTodoCodec().writeSummary(
      original.rawDocument,
      'Renamed',
    );
    final renamed = _editedRecord(original, renamedDocument);
    await store.saveLocalEdit(
      renamed,
      PendingTaskOperation.update(
        taskUid: 'task',
        calendarId: 'personal',
        changedProperties: const <String>{'SUMMARY'},
        createdAt: DateTime.utc(2026, 9, 14, 10),
      ),
    );

    final completedDocument = const VTodoCodec().writeCompletion(
      renamedDocument,
      isCompleted: true,
      now: DateTime.utc(2026, 9, 14, 11),
    );
    final completed = _editedRecord(renamed, completedDocument);
    await store.saveLocalEdit(
      completed,
      PendingTaskOperation.update(
        taskUid: 'task',
        calendarId: 'personal',
        changedProperties: const <String>{
          'STATUS',
          'PERCENT-COMPLETE',
          'COMPLETED',
        },
        createdAt: DateTime.utc(2026, 9, 14, 11),
      ),
    );

    final pending = await store.readPendingOperations();
    expect(pending, hasLength(1));
    expect(
      pending.single.changedProperties,
      <String>{'SUMMARY', 'STATUS', 'PERCENT-COMPLETE', 'COMPLETED'},
    );
    expect(pending.single.createdAt, DateTime.utc(2026, 9, 14, 10));
    expect((await store.readTask(
      calendarId: 'personal',
      taskUid: 'task',
    ))?.isDirty, isTrue);

    final serverRecord = TaskRecord(
      task: completed.task,
      href: completed.href,
      etag: '"server-etag"',
      rawDocument: completed.rawDocument,
      baseDocument: completed.rawDocument,
    );
    await store.completePendingWrite(serverRecord, pending.single.id);

    expect(await store.readPendingOperations(), isEmpty);
    final saved = await store.readTask(
      calendarId: 'personal',
      taskUid: 'task',
    );
    expect(saved?.isDirty, isFalse);
    expect(saved?.etag, '"server-etag"');
    expect(saved?.task.summary, 'Renamed');
    expect(saved?.task.status, CloudTaskStatus.completed);
  });

  test('upgrades the version 1 pending queue without losing operations',
      () async {
    final directory = await Directory.systemTemp.createTemp('cloud_tasks_db_');
    addTearDown(() => directory.delete(recursive: true));
    final databasePath = '${directory.path}/cloud_tasks.db';
    final versionOne = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE calendars (
  id TEXT PRIMARY KEY
)''');
          await database.execute('''
CREATE TABLE pending_operations (
  id TEXT PRIMARY KEY,
  task_uid TEXT NOT NULL,
  calendar_id TEXT NOT NULL,
  operation_type TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');
          await database.insert('pending_operations', <String, Object?>{
            'id': 'personal\\ntask\\nupdate',
            'task_uid': 'task',
            'calendar_id': 'personal',
            'operation_type': 'update',
            'created_at': DateTime.utc(2026, 9, 14).toIso8601String(),
          });
        },
      ),
    );
    await versionOne.close();

    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    addTearDown(store.close);
    final upgraded = await store.database;
    final columns = await upgraded.rawQuery(
      'PRAGMA table_info(pending_operations)',
    );

    expect(
      columns.map((column) => column['name']),
      containsAll(<String>[
        'changed_properties',
        'batch_id',
        'batch_phase',
      ]),
    );
    final calendarColumns = await upgraded.rawQuery(
      'PRAGMA table_info(calendars)',
    );
    expect(
      calendarColumns.map((column) => column['name']),
      containsAll(<String>[
        'owner_href',
        'is_shared_with_me',
        'can_be_shared',
      ]),
    );
    final pending = await store.readPendingOperations();
    expect(pending, hasLength(1));
    expect(pending.single.changedProperties, isEmpty);
    expect(pending.single.batchId, isNull);
    expect(pending.single.batchPhase, 0);
    final preferences = await store.readAppPreferences();
    expect(preferences.theme, CloudTasksTheme.system);
    expect(preferences.automaticSyncMinutes, 0);
    expect(preferences.syncOnResume, isTrue);
    expect(preferences.descendingManualOrder, isFalse);
    expect(preferences.lastCalendarId, isNull);
    expect(preferences.lastSmartView, isNull);

    final preferenceColumns = await upgraded.rawQuery(
      'PRAGMA table_info(app_preferences)',
    );
    expect(
      preferenceColumns.map((column) => column['name']),
      containsAll(<String>[
        'descending_manual_order',
        'last_calendar_id',
        'last_smart_view',
      ]),
    );
  });

  test('coalesces an offline create and update, then cancels before upload',
      () async {
    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final calendar = TaskCalendar(
      id: 'personal',
      accountId: 'account',
      href: Uri.parse('https://cloud.example/calendars/alice/personal/'),
      displayName: 'Personal',
      isReadOnly: false,
    );
    await store.saveCalendars(<TaskCalendar>[calendar]);
    final document = const VTodoCodec().create(
      uid: 'new-task',
      summary: 'New task',
      sortOrder: 100,
      now: DateTime.utc(2026, 9, 15),
    );
    final created = TaskRecord(
      task: const VTodoCodec().decode(document, calendarId: 'personal'),
      href: Uri.parse(
        'https://cloud.example/calendars/alice/personal/new-task.ics',
      ),
      rawDocument: document,
      isDirty: true,
    );
    await store.saveLocalEdit(
      created,
      PendingTaskOperation.create(
        taskUid: 'new-task',
        calendarId: 'personal',
      ),
    );

    final renamedDocument = const VTodoCodec().writeSummary(
      document,
      'Renamed before upload',
    );
    final renamed = _editedRecord(created, renamedDocument);
    await store.saveLocalEdit(
      renamed,
      PendingTaskOperation.update(
        taskUid: 'new-task',
        calendarId: 'personal',
        changedProperties: const <String>{'SUMMARY'},
      ),
    );

    var pending = await store.readPendingOperations();
    expect(pending, hasLength(1));
    expect(pending.single.type, PendingOperationType.create);
    expect((await store.readTaskCounts('account'))['personal'], 1);
    expect(
      (await store.readTask(
        calendarId: 'personal',
        taskUid: 'new-task',
      ))?.task.summary,
      'Renamed before upload',
    );

    await store.saveLocalEdit(
      renamed,
      PendingTaskOperation.delete(
        taskUid: 'new-task',
        calendarId: 'personal',
      ),
    );

    pending = await store.readPendingOperations();
    expect(pending, isEmpty);
    expect(
      await store.readTask(
        calendarId: 'personal',
        taskUid: 'new-task',
      ),
      isNull,
    );
  });

  test('queues and completes deletion of a synchronized task', () async {
    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final calendar = TaskCalendar(
      id: 'personal',
      accountId: 'account',
      href: Uri.parse('https://cloud.example/calendars/alice/personal/'),
      displayName: 'Personal',
      isReadOnly: false,
    );
    final record = _record('delete-me', 100);
    await store.replaceInitialSnapshot(calendar, <TaskRecord>[record]);
    final operation = PendingTaskOperation.delete(
      taskUid: 'delete-me',
      calendarId: 'personal',
    );

    await store.saveLocalEdit(record, operation);

    expect(await store.readAllTasks('personal'), isEmpty);
    final pending = await store.readPendingOperations();
    expect(pending.single.type, PendingOperationType.delete);

    await store.completePendingDelete(pending.single);

    expect(await store.readPendingOperations(), isEmpty);
    expect(
      await store.readTask(
        calendarId: 'personal',
        taskUid: 'delete-me',
      ),
      isNull,
    );
  });

  test('loads roots and subtasks together while preserving sibling queries',
      () async {
    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final calendar = TaskCalendar(
      id: 'personal',
      accountId: 'account',
      href: Uri.parse('https://cloud.example/calendars/alice/personal/'),
      displayName: 'Personal',
      isReadOnly: false,
    );
    final root = _record('root', 100);
    final laterChild = _record('later-child', 200, parentUid: 'root');
    final firstChild = _record('first-child', 100, parentUid: 'root');
    await store.replaceInitialSnapshot(
      calendar,
      <TaskRecord>[laterChild, root, firstChild],
    );

    final all = await store.readCalendarTasks('personal');
    final roots = await store.readAllTasks('personal');
    final children = await store.readSiblingGroup(
      calendarId: 'personal',
      parentUid: 'root',
    );

    expect(all.map((record) => record.task.uid).toSet(), {
      'root',
      'first-child',
      'later-child',
    });
    expect(roots.map((record) => record.task.uid), <String>['root']);
    expect(
      children.map((record) => record.task.uid),
      <String>['first-child', 'later-child'],
    );
  });

  test('queues a cross-list copy before deleting the source task', () async {
    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final source = TaskCalendar(
      id: 'source',
      accountId: 'account',
      href: Uri.parse('https://cloud.example/calendars/alice/source/'),
      displayName: 'Source',
      isReadOnly: false,
    );
    final destination = TaskCalendar(
      id: 'destination',
      accountId: 'account',
      href: Uri.parse('https://cloud.example/calendars/alice/destination/'),
      displayName: 'Destination',
      isReadOnly: false,
    );
    await store.saveCalendars(<TaskCalendar>[source, destination]);
    final sourceRecord = _record('move-me', 100, calendarId: source.id);
    await store.replaceInitialSnapshot(source, <TaskRecord>[sourceRecord]);
    await store.saveLocalEdit(
      sourceRecord.copyWith(isDirty: true),
      PendingTaskOperation.update(
        taskUid: 'move-me',
        calendarId: source.id,
        changedProperties: const <String>{'SUMMARY'},
        createdAt: DateTime.utc(2026, 9, 15, 10),
      ),
    );
    final copied = TaskRecord(
      task: sourceRecord.task.copyWith(calendarId: destination.id),
      href: destination.href.resolve('move-me.ics'),
      rawDocument: sourceRecord.rawDocument,
      isDirty: true,
    );
    final copyTime = DateTime.utc(2026, 9, 15, 12);

    await store.saveLocalEdits(<LocalTaskEdit>[
      LocalTaskEdit(
        record: copied,
        operation: PendingTaskOperation.create(
          taskUid: 'move-me',
          calendarId: destination.id,
          createdAt: copyTime,
          batchId: 'move-batch',
          batchPhase: 0,
        ),
      ),
      LocalTaskEdit(
        record: sourceRecord.copyWith(isDirty: true),
        operation: PendingTaskOperation.delete(
          taskUid: 'move-me',
          calendarId: source.id,
          createdAt: copyTime.add(const Duration(seconds: 1)),
          batchId: 'move-batch',
          batchPhase: 1,
        ),
      ),
    ]);

    final pending = await store.readPendingOperations();
    expect(
      pending.map((operation) => operation.type),
      <PendingOperationType>[
        PendingOperationType.create,
        PendingOperationType.delete,
      ],
    );
    expect(pending.first.createdAt, copyTime);
    expect(pending.last.createdAt, copyTime.add(const Duration(seconds: 1)));
    expect(pending.first.batchId, 'move-batch');
    expect(pending.first.batchPhase, 0);
    expect(pending.last.batchId, 'move-batch');
    expect(pending.last.batchPhase, 1);
    expect(await store.readCalendarTasks(source.id), isEmpty);
    expect(
      (await store.readCalendarTasks(destination.id)).single.task.uid,
      'move-me',
    );
  });

  test('persists app preferences independently from account removal', () async {
    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    const preferences = CloudTasksPreferences(
      theme: CloudTasksTheme.dark,
      automaticSyncMinutes: 30,
      syncOnResume: false,
      descendingManualOrder: true,
      lastCalendarId: 'personal',
      lastSmartView: SmartTaskView.today,
    );

    await store.saveAppPreferences(preferences);
    await store.clearAccount('account');
    final restored = await store.readAppPreferences();

    expect(restored.theme, CloudTasksTheme.dark);
    expect(restored.automaticSyncMinutes, 30);
    expect(restored.syncOnResume, isFalse);
    expect(restored.descendingManualOrder, isTrue);
    expect(restored.lastCalendarId, 'personal');
    expect(restored.lastSmartView, SmartTaskView.today);
  });

  test('applies server deltas without replacing dirty local records', () async {
    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final calendar = TaskCalendar(
      id: 'personal',
      accountId: 'account',
      href: Uri.parse('https://cloud.example/calendars/alice/personal/'),
      displayName: 'Personal',
      isReadOnly: false,
      syncToken: 'token-1',
    );
    final clean = _record('clean', 100);
    final dirty = _record('dirty', 200);
    await store.replaceInitialSnapshot(calendar, <TaskRecord>[clean, dirty]);
    await store.saveLocalEdit(
      dirty.copyWith(isDirty: true),
      PendingTaskOperation.update(
        taskUid: 'dirty',
        calendarId: 'personal',
        changedProperties: const <String>{'SUMMARY'},
      ),
    );

    await store.saveServerRecords(
      const <TaskRecord>[],
      deletedHrefs: <Uri>[clean.href, dirty.href],
      nextState: CalendarSyncState(
        calendarId: calendar.id,
        href: calendar.href,
        syncToken: 'token-2',
      ),
    );

    expect(
      await store.readTask(calendarId: 'personal', taskUid: 'clean'),
      isNull,
    );
    expect(
      await store.readTask(calendarId: 'personal', taskUid: 'dirty'),
      isNotNull,
    );
    expect((await store.readCalendars('account')).single.syncToken, 'token-2');
  });

  test('restores completed tasks in one durable local batch', () async {
    final store = SqliteTaskStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final calendar = TaskCalendar(
      id: 'personal',
      accountId: 'account',
      href: Uri.parse('https://cloud.example/calendars/alice/personal/'),
      displayName: 'Personal',
      isReadOnly: false,
    );
    final first = _completedRecord('first', 100);
    final second = _completedRecord('second', 200);
    await store.replaceInitialSnapshot(
      calendar,
      <TaskRecord>[first, second],
    );

    const codec = VTodoCodec();
    final now = DateTime.utc(2026, 9, 15, 12);
    await store.saveLocalEdits(<LocalTaskEdit>[
      for (final record in <TaskRecord>[first, second])
        LocalTaskEdit(
          record: _editedRecord(
            record,
            codec.writeCompletion(
              record.rawDocument,
              isCompleted: false,
              now: now,
            ),
          ),
          operation: PendingTaskOperation.update(
            taskUid: record.task.uid,
            calendarId: calendar.id,
            changedProperties: const <String>{
              'STATUS',
              'PERCENT-COMPLETE',
              'COMPLETED',
            },
          ),
        ),
    ]);

    final restored = await store.readCalendarTasks(calendar.id);
    expect(restored, hasLength(2));
    expect(restored.every((record) => !record.task.isCompleted), isTrue);
    expect(restored.map((record) => record.task.sortOrder), <int>[100, 200]);
    expect(restored.every((record) => record.isDirty), isTrue);
    expect(await store.readPendingOperations(), hasLength(2));
  });
}

TaskRecord _editedRecord(
  TaskRecord previous,
  ICalendarDocument document,
) {
  return TaskRecord(
    task: const VTodoCodec().decode(document, calendarId: 'personal'),
    href: previous.href,
    etag: previous.etag,
    rawDocument: document,
    baseDocument: previous.baseDocument,
    isDirty: true,
  );
}

TaskRecord _record(
  String uid,
  int order, {
  String? parentUid,
  String calendarId = 'personal',
}) {
  final parentLine = parentUid == null
      ? ''
      : 'RELATED-TO;RELTYPE=PARENT:$parentUid\n';
  final document = ICalendarDocument.parse('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:$uid
SUMMARY:$uid
X-APPLE-SORT-ORDER:$order
${parentLine}X-UNKNOWN:keep
END:VTODO
END:VCALENDAR
''');
  return TaskRecord(
    task: CloudTask(
      uid: uid,
      summary: uid,
      calendarId: calendarId,
      parentUid: parentUid,
      sortOrder: order,
    ),
    href: Uri.parse(
      'https://cloud.example/calendars/alice/$calendarId/$uid.ics',
    ),
    etag: '"$uid-etag"',
    rawDocument: document,
    baseDocument: document,
  );
}

TaskRecord _completedRecord(String uid, int order) {
  final document = ICalendarDocument.parse('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:$uid
SUMMARY:$uid
X-APPLE-SORT-ORDER:$order
STATUS:COMPLETED
PERCENT-COMPLETE:100
COMPLETED:20260915T110000Z
END:VTODO
END:VCALENDAR
''');
  return TaskRecord(
    task: const VTodoCodec().decode(document, calendarId: 'personal'),
    href: Uri.parse(
      'https://cloud.example/calendars/alice/personal/$uid.ics',
    ),
    etag: '"$uid-etag"',
    rawDocument: document,
    baseDocument: document,
  );
}
