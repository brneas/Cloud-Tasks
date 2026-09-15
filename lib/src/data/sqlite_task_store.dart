import 'package:cloud_tasks/src/app/cloud_tasks_preferences.dart';
import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/domain/task_view_filter.dart';
import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_codec.dart';
import 'package:cloud_tasks/src/sync/sync_contracts.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class SqliteTaskStore implements TaskStore {
  SqliteTaskStore({DatabaseFactory? factory, String? databasePath})
    : _databaseFactory = factory,
      _databasePath = databasePath;

  final DatabaseFactory? _databaseFactory;
  final String? _databasePath;
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final factory = _databaseFactory ?? databaseFactory;
    final resolvedPath =
        _databasePath ??
        path.join(await factory.getDatabasesPath(), 'cloud_tasks.db');
    final opened = await factory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    final existing = _database;
    _database = null;
    await existing?.close();
  }

  Future<void> saveCalendars(Iterable<TaskCalendar> calendars) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final calendar in calendars) {
        await _upsertCalendar(transaction, calendar);
      }
    });
  }

  Future<void> replaceCalendarSnapshot(
    String accountId,
    Iterable<TaskCalendar> calendars,
  ) async {
    final snapshot = List<TaskCalendar>.of(calendars);
    final snapshotIds = snapshot.map((calendar) => calendar.id).toSet();
    final db = await database;
    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'calendars',
        columns: <String>['id'],
        where: 'account_id = ?',
        whereArgs: <Object?>[accountId],
      );
      for (final row in existing) {
        final id = row['id']! as String;
        if (!snapshotIds.contains(id)) {
          await transaction.delete(
            'calendars',
            where: 'id = ?',
            whereArgs: <Object?>[id],
          );
        }
      }
      for (final calendar in snapshot) {
        await _upsertCalendar(transaction, calendar);
      }
    });
  }

  Future<List<TaskCalendar>> readCalendars(String accountId) async {
    final db = await database;
    final rows = await db.query(
      'calendars',
      where: 'account_id = ?',
      whereArgs: <Object?>[accountId],
      orderBy:
          'CASE WHEN sort_order IS NULL THEN 1 ELSE 0 END, '
          'sort_order ASC, display_name COLLATE NOCASE ASC',
    );
    return List<TaskCalendar>.unmodifiable(rows.map(_calendarFromRow));
  }

  Future<String?> readDefaultCalendarId(String accountId) async {
    final db = await database;
    final rows = await db.query(
      'account_preferences',
      columns: const <String>['default_calendar_id'],
      where: 'account_id = ?',
      whereArgs: <Object?>[accountId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['default_calendar_id'] as String?;
  }

  Future<void> setDefaultCalendarId(
    String accountId,
    String? calendarId,
  ) async {
    final db = await database;
    if (calendarId == null) {
      await db.delete(
        'account_preferences',
        where: 'account_id = ?',
        whereArgs: <Object?>[accountId],
      );
      return;
    }
    await _upsert(
      db,
      'account_preferences',
      'account_id',
      accountId,
      <String, Object?>{
        'account_id': accountId,
        'default_calendar_id': calendarId,
      },
    );
  }

  Future<Map<String, int>> readTaskCounts(String accountId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
SELECT tasks.calendar_id, COUNT(*) AS task_count
FROM tasks
INNER JOIN calendars ON calendars.id = tasks.calendar_id
WHERE calendars.account_id = ? AND tasks.is_deleted = 0
GROUP BY tasks.calendar_id
''',
      <Object?>[accountId],
    );
    return Map<String, int>.unmodifiable(<String, int>{
      for (final row in rows)
        row['calendar_id']! as String: row['task_count']! as int,
    });
  }

  Future<void> replaceInitialSnapshot(
    TaskCalendar calendar,
    Iterable<TaskRecord> records,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      await _upsertCalendar(transaction, calendar);
      await transaction.delete(
        'tasks',
        where: 'calendar_id = ? AND is_dirty = 0',
        whereArgs: <Object?>[calendar.id],
      );
      for (final record in records) {
        await _upsertServerRecord(transaction, record);
      }
    });
  }

  Future<List<TaskRecord>> readAllTasks(String calendarId) {
    return readSiblingGroup(calendarId: calendarId, parentUid: null);
  }

  Future<List<TaskRecord>> readCalendarTasks(String calendarId) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'calendar_id = ? AND is_deleted = 0',
      whereArgs: <Object?>[calendarId],
      orderBy:
          'CASE WHEN manual_order IS NULL THEN 1 ELSE 0 END, '
          'manual_order ASC, uid ASC',
    );
    return List<TaskRecord>.unmodifiable(rows.map(_taskRecordFromRow));
  }

  @override
  Future<List<TaskRecord>> readSiblingGroup({
    required String calendarId,
    required String? parentUid,
  }) async {
    final db = await database;
    final parentClause = parentUid == null
        ? 'parent_uid IS NULL'
        : 'parent_uid = ?';
    final rows = await db.query(
      'tasks',
      where: 'calendar_id = ? AND $parentClause AND is_deleted = 0',
      whereArgs: <Object?>[calendarId, if (parentUid != null) parentUid],
      orderBy:
          'CASE WHEN manual_order IS NULL THEN 1 ELSE 0 END, '
          'manual_order ASC, uid ASC',
    );
    return List<TaskRecord>.unmodifiable(rows.map(_taskRecordFromRow));
  }

  @override
  Future<void> saveServerRecords(
    Iterable<TaskRecord> records, {
    required CalendarSyncState nextState,
    Iterable<Uri> deletedHrefs = const <Uri>[],
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final record in records) {
        await _upsertServerRecord(transaction, record);
      }
      for (final href in deletedHrefs) {
        await transaction.delete(
          'tasks',
          where: 'href = ? AND is_dirty = 0',
          whereArgs: <Object?>[href.toString()],
        );
      }
      await transaction.update(
        'calendars',
        <String, Object?>{'sync_token': nextState.syncToken},
        where: 'id = ?',
        whereArgs: <Object?>[nextState.calendarId],
      );
    });
  }

  @override
  Future<void> saveLocalEdit(
    TaskRecord record,
    PendingTaskOperation operation,
  ) async {
    await saveLocalEdits(<LocalTaskEdit>[
      LocalTaskEdit(record: record, operation: operation),
    ]);
  }

  Future<void> saveLocalEdits(Iterable<LocalTaskEdit> edits) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final edit in edits) {
        final record = edit.record;
        final operation = edit.operation;
        final existing = await transaction.query(
          'pending_operations',
          columns: <String>[
            'operation_type',
            'changed_properties',
            'created_at',
            'batch_id',
            'batch_phase',
          ],
          where: 'calendar_id = ? AND task_uid = ?',
          whereArgs: <Object?>[operation.calendarId, operation.taskUid],
        );
        final hasPendingCreate = existing.any(
          (row) => row['operation_type'] == PendingOperationType.create.name,
        );
        if (hasPendingCreate && operation.type == PendingOperationType.delete) {
          await transaction.delete(
            'pending_operations',
            where: 'calendar_id = ? AND task_uid = ?',
            whereArgs: <Object?>[operation.calendarId, operation.taskUid],
          );
          await transaction.delete(
            'tasks',
            where: 'calendar_id = ? AND uid = ?',
            whereArgs: <Object?>[operation.calendarId, operation.taskUid],
          );
          continue;
        }

        final effectiveType =
            hasPendingCreate && operation.type == PendingOperationType.update
            ? PendingOperationType.create
            : operation.type;
        final changedProperties = <String>{...operation.changedProperties};
        var createdAt = operation.createdAt.toUtc();
        var batchId = operation.batchId;
        var batchPhase = operation.batchPhase;
        for (final row in existing) {
          changedProperties.addAll(
            _decodeChangedProperties(row['changed_properties'] as String?),
          );
          final existingCreatedAt = DateTime.parse(
            row['created_at']! as String,
          );
          if (effectiveType != PendingOperationType.delete &&
              existingCreatedAt.isBefore(createdAt)) {
            createdAt = existingCreatedAt;
          }
          if (batchId == null && row['batch_id'] != null) {
            batchId = row['batch_id']! as String;
            batchPhase = row['batch_phase']! as int;
          }
        }
        final effectiveId = _pendingOperationId(
          operation.calendarId,
          operation.taskUid,
          effectiveType,
        );
        await transaction.delete(
          'pending_operations',
          where: 'calendar_id = ? AND task_uid = ?',
          whereArgs: <Object?>[operation.calendarId, operation.taskUid],
        );

        final values = _taskValues(record)
          ..['is_dirty'] = 1
          ..['is_deleted'] = effectiveType == PendingOperationType.delete
              ? 1
              : 0;
        await _upsert(
          transaction,
          'tasks',
          'href',
          record.href.toString(),
          values,
        );
        await transaction.insert('pending_operations', <String, Object?>{
          'id': effectiveId,
          'task_uid': operation.taskUid,
          'calendar_id': operation.calendarId,
          'operation_type': effectiveType.name,
          'created_at': createdAt.toIso8601String(),
          'changed_properties': _encodeChangedProperties(changedProperties),
          'batch_id': batchId,
          'batch_phase': batchPhase,
        });
      }
    });
  }

  @override
  Future<List<PendingTaskOperation>> readPendingOperations() async {
    final db = await database;
    final rows = await db.query(
      'pending_operations',
      orderBy: 'created_at, id',
    );
    return List<PendingTaskOperation>.unmodifiable(
      rows.map((row) {
        return PendingTaskOperation(
          id: row['id']! as String,
          taskUid: row['task_uid']! as String,
          calendarId: row['calendar_id']! as String,
          type: PendingOperationType.values.byName(
            row['operation_type']! as String,
          ),
          createdAt: DateTime.parse(row['created_at']! as String),
          changedProperties: _decodeChangedProperties(
            row['changed_properties'] as String?,
          ),
          batchId: row['batch_id'] as String?,
          batchPhase: row['batch_phase']! as int,
        );
      }),
    );
  }

  Future<TaskRecord?> readTask({
    required String calendarId,
    required String taskUid,
  }) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'calendar_id = ? AND uid = ?',
      whereArgs: <Object?>[calendarId, taskUid],
      limit: 1,
    );
    return rows.isEmpty ? null : _taskRecordFromRow(rows.first);
  }

  Future<void> completePendingWrite(
    TaskRecord serverRecord,
    String operationId,
  ) async {
    final cleanRecord = serverRecord.copyWith(
      baseDocument: serverRecord.rawDocument,
      isDirty: false,
    );
    final db = await database;
    await db.transaction((transaction) async {
      await _upsert(
        transaction,
        'tasks',
        'href',
        cleanRecord.href.toString(),
        _taskValues(cleanRecord),
      );
      await transaction.delete(
        'pending_operations',
        where: 'id = ?',
        whereArgs: <Object?>[operationId],
      );
    });
  }

  Future<void> deletePendingOperation(String operationId) async {
    final db = await database;
    await db.delete(
      'pending_operations',
      where: 'id = ?',
      whereArgs: <Object?>[operationId],
    );
  }

  Future<void> completePendingDelete(PendingTaskOperation operation) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'tasks',
        where: 'calendar_id = ? AND uid = ?',
        whereArgs: <Object?>[operation.calendarId, operation.taskUid],
      );
      await transaction.delete(
        'pending_operations',
        where: 'id = ?',
        whereArgs: <Object?>[operation.id],
      );
    });
  }

  Future<void> clearAccount(String accountId) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'account_preferences',
        where: 'account_id = ?',
        whereArgs: <Object?>[accountId],
      );
      await transaction.delete(
        'calendars',
        where: 'account_id = ?',
        whereArgs: <Object?>[accountId],
      );
    });
  }

  Future<CloudTasksPreferences> readAppPreferences() async {
    final db = await database;
    final rows = await db.query('app_preferences', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      return const CloudTasksPreferences();
    }
    final row = rows.first;
    final themeName = row['theme']! as String;
    return CloudTasksPreferences(
      theme: CloudTasksTheme.values.firstWhere(
        (theme) => theme.name == themeName,
        orElse: () => CloudTasksTheme.system,
      ),
      automaticSyncMinutes: row['automatic_sync_minutes']! as int,
      syncOnResume: row['sync_on_resume'] == 1,
      descendingManualOrder: row['descending_manual_order'] == 1,
      lastCalendarId: row['last_calendar_id'] as String?,
      lastSmartView: _smartTaskViewFromName(row['last_smart_view']),
    );
  }

  Future<void> saveAppPreferences(CloudTasksPreferences preferences) async {
    final db = await database;
    await _upsert(db, 'app_preferences', 'id', 1, <String, Object?>{
      'id': 1,
      'theme': preferences.theme.name,
      'automatic_sync_minutes': preferences.automaticSyncMinutes,
      'sync_on_resume': preferences.syncOnResume ? 1 : 0,
      'descending_manual_order': preferences.descendingManualOrder ? 1 : 0,
      'last_calendar_id': preferences.lastCalendarId,
      'last_smart_view': preferences.lastSmartView?.name,
    });
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
CREATE TABLE calendars (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  href TEXT NOT NULL,
  display_name TEXT NOT NULL,
  color TEXT,
  sort_order INTEGER,
  is_read_only INTEGER NOT NULL DEFAULT 1,
  owner_href TEXT,
  is_shared_with_me INTEGER NOT NULL DEFAULT 0,
  can_be_shared INTEGER NOT NULL DEFAULT 0,
  sync_token TEXT
)''');
    await database.execute('''
CREATE INDEX calendars_account_idx ON calendars(account_id, sort_order)
''');
    await database.execute('''
CREATE TABLE account_preferences (
  account_id TEXT PRIMARY KEY,
  default_calendar_id TEXT NOT NULL
)''');
    await database.execute('''
CREATE TABLE tasks (
  href TEXT PRIMARY KEY,
  calendar_id TEXT NOT NULL REFERENCES calendars(id) ON DELETE CASCADE,
  uid TEXT NOT NULL,
  summary TEXT NOT NULL,
  parent_uid TEXT,
  manual_order INTEGER,
  status TEXT,
  etag TEXT,
  raw_document TEXT NOT NULL,
  base_document TEXT,
  is_dirty INTEGER NOT NULL DEFAULT 0,
  is_deleted INTEGER NOT NULL DEFAULT 0
)''');
    await database.execute('''
CREATE UNIQUE INDEX tasks_calendar_uid_idx ON tasks(calendar_id, uid)
''');
    await database.execute('''
CREATE INDEX tasks_sibling_order_idx
ON tasks(calendar_id, parent_uid, manual_order)
''');
    await database.execute('''
CREATE INDEX tasks_calendar_status_idx
ON tasks(calendar_id, is_deleted, status)
''');
    await database.execute('''
CREATE TABLE pending_operations (
  id TEXT PRIMARY KEY,
  task_uid TEXT NOT NULL,
  calendar_id TEXT NOT NULL REFERENCES calendars(id) ON DELETE CASCADE,
  operation_type TEXT NOT NULL,
  created_at TEXT NOT NULL,
  changed_properties TEXT NOT NULL DEFAULT '',
  batch_id TEXT,
  batch_phase INTEGER NOT NULL DEFAULT 0
)''');
    await database.execute('''
CREATE TABLE app_preferences (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  theme TEXT NOT NULL DEFAULT 'system',
  automatic_sync_minutes INTEGER NOT NULL DEFAULT 0,
  sync_on_resume INTEGER NOT NULL DEFAULT 1,
  descending_manual_order INTEGER NOT NULL DEFAULT 0,
  last_calendar_id TEXT,
  last_smart_view TEXT
)''');
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int _,
  ) async {
    if (oldVersion < 2) {
      await database.execute(
        "ALTER TABLE pending_operations ADD COLUMN "
        "changed_properties TEXT NOT NULL DEFAULT ''",
      );
    }
    if (oldVersion < 3) {
      await database.execute(
        'ALTER TABLE calendars ADD COLUMN owner_href TEXT',
      );
      await database.execute(
        'ALTER TABLE calendars ADD COLUMN '
        'is_shared_with_me INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        'ALTER TABLE calendars ADD COLUMN '
        'can_be_shared INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute('''
CREATE TABLE account_preferences (
  account_id TEXT PRIMARY KEY,
  default_calendar_id TEXT NOT NULL
)''');
    }
    if (oldVersion < 4) {
      await database.execute(
        'ALTER TABLE pending_operations ADD COLUMN batch_id TEXT',
      );
      await database.execute(
        'ALTER TABLE pending_operations ADD COLUMN '
        'batch_phase INTEGER NOT NULL DEFAULT 0',
      );
      final taskTable = await database.query(
        'sqlite_master',
        columns: const <String>['name'],
        where: "type = 'table' AND name = 'tasks'",
        limit: 1,
      );
      if (taskTable.isNotEmpty) {
        await database.execute('''
CREATE INDEX tasks_calendar_status_idx
ON tasks(calendar_id, is_deleted, status)
''');
      }
      await database.execute('''
CREATE TABLE app_preferences (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  theme TEXT NOT NULL DEFAULT 'system',
  automatic_sync_minutes INTEGER NOT NULL DEFAULT 0,
  sync_on_resume INTEGER NOT NULL DEFAULT 1
)''');
    }
    if (oldVersion < 5) {
      await database.execute(
        'ALTER TABLE app_preferences ADD COLUMN '
        'descending_manual_order INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        'ALTER TABLE app_preferences ADD COLUMN last_calendar_id TEXT',
      );
      await database.execute(
        'ALTER TABLE app_preferences ADD COLUMN last_smart_view TEXT',
      );
    }
  }

  static Future<void> _upsertCalendar(
    DatabaseExecutor database,
    TaskCalendar calendar,
  ) {
    return _upsert(database, 'calendars', 'id', calendar.id, <String, Object?>{
      'id': calendar.id,
      'account_id': calendar.accountId,
      'href': calendar.href.toString(),
      'display_name': calendar.displayName,
      'color': calendar.color,
      'sort_order': calendar.sortOrder,
      'is_read_only': calendar.isReadOnly ? 1 : 0,
      'owner_href': calendar.ownerHref,
      'is_shared_with_me': calendar.isSharedWithMe ? 1 : 0,
      'can_be_shared': calendar.canBeShared ? 1 : 0,
      'sync_token': calendar.syncToken,
    });
  }

  static SmartTaskView? _smartTaskViewFromName(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final view in SmartTaskView.values) {
      if (view.name == value) {
        return view;
      }
    }
    return null;
  }

  static Future<void> _upsertServerRecord(
    DatabaseExecutor database,
    TaskRecord record,
  ) async {
    final existing = await database.query(
      'tasks',
      columns: <String>['is_dirty'],
      where: 'href = ?',
      whereArgs: <Object?>[record.href.toString()],
      limit: 1,
    );
    if (existing.isNotEmpty && existing.first['is_dirty'] == 1) {
      return;
    }
    await _upsert(
      database,
      'tasks',
      'href',
      record.href.toString(),
      _taskValues(record),
    );
  }

  static Map<String, Object?> _taskValues(TaskRecord record) {
    return <String, Object?>{
      'href': record.href.toString(),
      'calendar_id': record.task.calendarId,
      'uid': record.task.uid,
      'summary': record.task.summary,
      'parent_uid': record.task.parentUid,
      'manual_order': record.task.sortOrder,
      'status': record.task.status?.icalendarValue,
      'etag': record.etag,
      'raw_document': record.rawDocument.serialize(),
      'base_document': record.baseDocument?.serialize(),
      'is_dirty': record.isDirty ? 1 : 0,
      'is_deleted': 0,
    };
  }

  static TaskCalendar _calendarFromRow(Map<String, Object?> row) {
    return TaskCalendar(
      id: row['id']! as String,
      accountId: row['account_id']! as String,
      href: Uri.parse(row['href']! as String),
      displayName: row['display_name']! as String,
      color: row['color'] as String?,
      sortOrder: row['sort_order'] as int?,
      isReadOnly: row['is_read_only'] == 1,
      syncToken: row['sync_token'] as String?,
      ownerHref: row['owner_href'] as String?,
      isSharedWithMe: row['is_shared_with_me'] == 1,
      canBeShared: row['can_be_shared'] == 1,
    );
  }

  static TaskRecord _taskRecordFromRow(Map<String, Object?> row) {
    final rawDocument = ICalendarDocument.parse(row['raw_document']! as String);
    final baseValue = row['base_document'] as String?;
    return TaskRecord(
      task: const VTodoCodec().decode(
        rawDocument,
        calendarId: row['calendar_id']! as String,
      ),
      href: Uri.parse(row['href']! as String),
      etag: row['etag'] as String?,
      rawDocument: rawDocument,
      baseDocument: baseValue == null
          ? null
          : ICalendarDocument.parse(baseValue),
      isDirty: row['is_dirty'] == 1,
    );
  }

  static Future<void> _upsert(
    DatabaseExecutor database,
    String table,
    String keyColumn,
    Object keyValue,
    Map<String, Object?> values,
  ) async {
    final updated = await database.update(
      table,
      values,
      where: '$keyColumn = ?',
      whereArgs: <Object?>[keyValue],
    );
    if (updated == 0) {
      await database.insert(table, values);
    }
  }

  static String _encodeChangedProperties(Iterable<String> properties) {
    final normalized =
        properties.map((property) => property.toUpperCase()).toSet().toList()
          ..sort();
    return normalized.join(',');
  }

  static String _pendingOperationId(
    String calendarId,
    String taskUid,
    PendingOperationType type,
  ) {
    return '$calendarId\n$taskUid\n${type.name}';
  }

  static Set<String> _decodeChangedProperties(String? encoded) {
    if (encoded == null || encoded.isEmpty) {
      return const <String>{};
    }
    return Set<String>.unmodifiable(
      encoded
          .split(',')
          .map((property) => property.trim().toUpperCase())
          .where((property) => property.isNotEmpty),
    );
  }
}
