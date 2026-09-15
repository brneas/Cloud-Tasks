import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';

enum PendingOperationType { create, update, delete }

class TaskRecord {
  const TaskRecord({
    required this.task,
    required this.href,
    required this.rawDocument,
    this.etag,
    this.baseDocument,
    this.isDirty = false,
  });

  final CloudTask task;
  final Uri href;
  final String? etag;
  final ICalendarDocument rawDocument;
  final ICalendarDocument? baseDocument;
  final bool isDirty;

  TaskRecord copyWith({
    CloudTask? task,
    Uri? href,
    String? etag,
    bool clearEtag = false,
    ICalendarDocument? rawDocument,
    ICalendarDocument? baseDocument,
    bool? isDirty,
  }) {
    return TaskRecord(
      task: task ?? this.task,
      href: href ?? this.href,
      etag: clearEtag ? null : etag ?? this.etag,
      rawDocument: rawDocument ?? this.rawDocument,
      baseDocument: baseDocument ?? this.baseDocument,
      isDirty: isDirty ?? this.isDirty,
    );
  }
}

class CalendarSyncState {
  const CalendarSyncState({
    required this.calendarId,
    required this.href,
    this.syncToken,
  });

  final String calendarId;
  final Uri href;
  final String? syncToken;
}

class PendingTaskOperation {
  const PendingTaskOperation({
    required this.id,
    required this.taskUid,
    required this.calendarId,
    required this.type,
    required this.createdAt,
    this.changedProperties = const <String>{},
    this.batchId,
    this.batchPhase = 0,
  });

  final String id;
  final String taskUid;
  final String calendarId;
  final PendingOperationType type;
  final DateTime createdAt;
  final Set<String> changedProperties;
  final String? batchId;
  final int batchPhase;

  factory PendingTaskOperation.update({
    required String taskUid,
    required String calendarId,
    required Iterable<String> changedProperties,
    DateTime? createdAt,
    String? batchId,
    int batchPhase = 0,
  }) {
    return PendingTaskOperation(
      id: '$calendarId\n$taskUid\nupdate',
      taskUid: taskUid,
      calendarId: calendarId,
      type: PendingOperationType.update,
      createdAt: createdAt ?? DateTime.now().toUtc(),
      changedProperties: Set<String>.unmodifiable(
        changedProperties.map((property) => property.toUpperCase()),
      ),
      batchId: batchId,
      batchPhase: batchPhase,
    );
  }

  factory PendingTaskOperation.create({
    required String taskUid,
    required String calendarId,
    DateTime? createdAt,
    String? batchId,
    int batchPhase = 0,
  }) {
    return PendingTaskOperation(
      id: '$calendarId\n$taskUid\ncreate',
      taskUid: taskUid,
      calendarId: calendarId,
      type: PendingOperationType.create,
      createdAt: createdAt ?? DateTime.now().toUtc(),
      batchId: batchId,
      batchPhase: batchPhase,
    );
  }

  factory PendingTaskOperation.delete({
    required String taskUid,
    required String calendarId,
    DateTime? createdAt,
    String? batchId,
    int batchPhase = 0,
  }) {
    return PendingTaskOperation(
      id: '$calendarId\n$taskUid\ndelete',
      taskUid: taskUid,
      calendarId: calendarId,
      type: PendingOperationType.delete,
      createdAt: createdAt ?? DateTime.now().toUtc(),
      batchId: batchId,
      batchPhase: batchPhase,
    );
  }
}

class LocalTaskEdit {
  const LocalTaskEdit({required this.record, required this.operation});

  final TaskRecord record;
  final PendingTaskOperation operation;
}

abstract interface class TaskStore {
  Future<List<TaskRecord>> readSiblingGroup({
    required String calendarId,
    required String? parentUid,
  });

  Future<void> saveServerRecords(
    Iterable<TaskRecord> records, {
    required CalendarSyncState nextState,
    Iterable<Uri> deletedHrefs = const <Uri>[],
  });

  Future<void> saveLocalEdit(
    TaskRecord record,
    PendingTaskOperation operation,
  );

  Future<List<PendingTaskOperation>> readPendingOperations();
}

abstract interface class CalDavGateway {
  Future<List<CalendarSyncState>> discoverTaskCalendars();

  Future<CalendarDelta> readChanges(CalendarSyncState state);

  Future<TaskRecord> putTask(TaskRecord record);

  Future<void> deleteTask(TaskRecord record);
}

class CalendarDelta {
  const CalendarDelta({
    required this.changed,
    required this.deletedHrefs,
    required this.nextSyncToken,
  });

  final List<TaskRecord> changed;
  final List<Uri> deletedHrefs;
  final String? nextSyncToken;
}
