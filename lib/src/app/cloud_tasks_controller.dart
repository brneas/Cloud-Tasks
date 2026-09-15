import 'dart:async';
import 'dart:math';

import 'package:cloud_tasks/src/account/account_store.dart';
import 'package:cloud_tasks/src/account/login_flow_v2.dart';
import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_preferences.dart';
import 'package:cloud_tasks/src/caldav/caldav_calendar_writer.dart';
import 'package:cloud_tasks/src/caldav/caldav_calendar_sharing_service.dart';
import 'package:cloud_tasks/src/caldav/caldav_discovery_service.dart';
import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/caldav/caldav_task_reader.dart';
import 'package:cloud_tasks/src/caldav/caldav_task_writer.dart';
import 'package:cloud_tasks/src/data/sqlite_task_store.dart';
import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/domain/task_access_policy.dart';
import 'package:cloud_tasks/src/domain/task_recurrence.dart';
import 'package:cloud_tasks/src/domain/task_view_filter.dart';
import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_archive.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_codec.dart';
import 'package:cloud_tasks/src/network/authenticated_client.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:cloud_tasks/src/notifications/task_notification_scheduler.dart';
import 'package:cloud_tasks/src/ordering/manual_order_service.dart';
import 'package:cloud_tasks/src/ordering/task_hierarchy.dart';
import 'package:cloud_tasks/src/sync/background_sync_scheduler.dart';
import 'package:cloud_tasks/src/sync/initial_sync_service.dart';
import 'package:cloud_tasks/src/sync/sync_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

enum CloudTasksViewState {
  starting,
  signedOut,
  authenticating,
  syncing,
  ready,
  error,
}

class CloudTasksController extends ChangeNotifier {
  CloudTasksController({
    required AccountStore accountStore,
    required SqliteTaskStore taskStore,
    required BrowserLauncher browserLauncher,
    TaskNotificationScheduler notificationScheduler =
        const NoopTaskNotificationScheduler(),
    BackgroundSyncScheduler backgroundSyncScheduler =
        const NoopBackgroundSyncScheduler(),
  })  : _accountStore = accountStore,
        _taskStore = taskStore,
        _browserLauncher = browserLauncher,
        _notificationScheduler = notificationScheduler,
        _backgroundSyncScheduler = backgroundSyncScheduler;

  static const _ordering = ManualOrderService();
  static const _hierarchy = TaskHierarchy();
  static const _codec = VTodoCodec();
  static const _archive = VTodoArchive();
  static const _recurrence = TaskRecurrenceService();
  static const _viewFilter = TaskViewFilter();
  static const _accessPolicy = TaskAccessPolicy();
  static const _writebackDelay = Duration(milliseconds: 500);
  static const _notificationDelay = Duration(milliseconds: 250);

  final AccountStore _accountStore;
  final SqliteTaskStore _taskStore;
  final BrowserLauncher _browserLauncher;
  final TaskNotificationScheduler _notificationScheduler;
  final BackgroundSyncScheduler _backgroundSyncScheduler;

  CloudTasksViewState _state = CloudTasksViewState.starting;
  NextcloudAccount? _account;
  List<TaskCalendar> _calendars = const <TaskCalendar>[];
  List<TaskRecord> _tasks = const <TaskRecord>[];
  Map<String, int> _taskCounts = const <String, int>{};
  Map<String, TaskCalendar> _calendarsById = const <String, TaskCalendar>{};
  Map<String, TaskRecord> _recordsByKey = const <String, TaskRecord>{};
  Map<String, int> _descendantCounts = const <String, int>{};
  List<String> _availableTags = const <String>[];
  String? _selectedCalendarId;
  String? _defaultCalendarId;
  SmartTaskView? _selectedSmartView;
  String _searchQuery = '';
  String? _selectedTag;
  String? _message;
  bool _descending = false;
  bool _isSaving = false;
  bool _syncInProgress = false;
  bool _writebackInProgress = false;
  bool _writebackPreparing = false;
  bool _writebackRequested = false;
  bool _refreshAfterWriteback = false;
  bool _disposed = false;
  Future<void> _localEditQueue = Future<void>.value();
  Future<void> _notificationQueue = Future<void>.value();
  final Set<String> _locallySavingTaskKeys = <String>{};
  final Set<String> _uploadingTaskKeys = <String>{};
  int _viewSelectionGeneration = 0;
  Future<void>? _initialization;
  Future<void>? _activeWriteback;
  CloudTasksPreferences _preferences = const CloudTasksPreferences();
  DateTime? _lastSuccessfulSync;
  Timer? _automaticSyncTimer;
  Timer? _notificationTimer;
  Timer? _writebackTimer;

  CloudTasksViewState get state => _state;
  NextcloudAccount? get account => _account;
  List<TaskCalendar> get calendars => _calendars;
  String? get selectedCalendarId => _selectedCalendarId;
  String? get defaultCalendarId => _defaultCalendarId;
  SmartTaskView? get selectedSmartView => _selectedSmartView;
  String get searchQuery => _searchQuery;
  String? get selectedTag => _selectedTag;
  bool get isSmartView => _selectedSmartView != null;
  String? get message => _message;
  bool get descending => _descending;
  bool get isSaving => _isSaving;
  bool get isSyncing => _syncInProgress;
  bool get isUploading => _writebackInProgress;
  bool get hasCachedData => _calendars.isNotEmpty;
  CloudTasksPreferences get preferences => _preferences;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;
  bool get hasActiveFilters =>
      _searchQuery.trim().isNotEmpty || _selectedTag != null;

  int taskCount(String calendarId) => _taskCounts[calendarId] ?? 0;

  TaskCalendar? get selectedCalendar {
    if (isSmartView) {
      return null;
    }
    return _calendarsById[_selectedCalendarId];
  }

  TaskCalendar? get defaultCalendar {
    return _calendarsById[_defaultCalendarId];
  }

  TaskCalendar? get taskCreationCalendar {
    final selected = selectedCalendar;
    if (!isSmartView) {
      return selected != null && !selected.isReadOnly ? selected : null;
    }
    final fallback = defaultCalendar;
    return fallback != null && !fallback.isReadOnly ? fallback : null;
  }

  bool get selectedCalendarIsWritable =>
      !(selectedCalendar?.isReadOnly ?? true);

  bool get canEditSelectedCalendar =>
      state == CloudTasksViewState.ready &&
      !_isSaving &&
      selectedCalendarIsWritable;

  bool get canCreateTask =>
      state == CloudTasksViewState.ready &&
      !_isSaving &&
      taskCreationCalendar != null;

  bool canCreateTaskIn(String calendarId) =>
      state == CloudTasksViewState.ready &&
      !_isSaving &&
      _calendars.any(
        (calendar) => calendar.id == calendarId && !calendar.isReadOnly,
      );

  bool canManageCalendar(TaskCalendar calendar) =>
      state == CloudTasksViewState.ready &&
      !_isSaving &&
      !calendar.isReadOnly &&
      !calendar.isSharedWithMe;

  bool canShareCalendar(TaskCalendar calendar) =>
      canManageCalendar(calendar) && calendar.canBeShared;

  bool get canReorderSelectedView =>
      !isSmartView &&
      canEditSelectedCalendar &&
      _locallySavingTaskKeys.isEmpty &&
      !_writebackInProgress &&
      _searchQuery.trim().isEmpty &&
      _selectedTag == null;

  bool get canRestoreCompletedTasks =>
      selectedCalendar != null &&
      selectedCalendarIsWritable &&
      state == CloudTasksViewState.ready &&
      !_isSaving &&
      _locallySavingTaskKeys.isEmpty &&
      !_writebackInProgress;

  String get viewTitle {
    final smart = _selectedSmartView;
    if (smart == null) {
      return selectedCalendar?.displayName ?? 'Cloud Tasks';
    }
    return switch (smart) {
      SmartTaskView.all => 'All tasks',
      SmartTaskView.important => 'Important',
      SmartTaskView.current => 'Current',
      SmartTaskView.today => 'Today',
      SmartTaskView.nextSevenDays => 'Week',
      SmartTaskView.upcoming => 'Upcoming',
      SmartTaskView.overdue => 'Overdue',
      SmartTaskView.completed => 'Completed',
    };
  }

  String get viewSubtitle {
    if (!isSmartView) {
      final calendar = selectedCalendar;
      if (calendar?.isSharedWithMe ?? false) {
        return calendar!.isReadOnly
            ? 'Shared • Read only'
            : 'Shared • Can edit';
      }
      return (calendar?.isReadOnly ?? false) ? 'Read only' : 'Nextcloud list';
    }
    return 'Across ${_calendars.length} task '
        '${_calendars.length == 1 ? 'list' : 'lists'}';
  }

  List<String> get availableTags => _availableTags;

  TaskCalendar? calendarForRecord(TaskRecord record) {
    return _calendarsById[record.task.calendarId];
  }

  bool canEditRecord(TaskRecord record) {
    final calendar = calendarForRecord(record);
    return state == CloudTasksViewState.ready &&
        !_isSaving &&
        !_writebackPreparing &&
        !_locallySavingTaskKeys.contains(
          _taskKey(record.task.calendarId, record.task.uid),
        ) &&
        !_uploadingTaskKeys.contains(
          _taskKey(record.task.calendarId, record.task.uid),
        ) &&
        calendar != null &&
        _accessPolicy.canEdit(
          calendarReadOnly: calendar.isReadOnly,
          calendarSharedWithMe: calendar.isSharedWithMe,
          privacy: record.task.privacy,
        );
  }

  bool canEditPrivacy(TaskRecord record) {
    final calendar = calendarForRecord(record);
    return canEditRecord(record) &&
        calendar != null &&
        _accessPolicy.canEditPrivacy(
          calendarSharedWithMe: calendar.isSharedWithMe,
        );
  }

  bool canMoveRecordTo(TaskRecord record, TaskCalendar destination) {
    final source = calendarForRecord(record);
    return source != null &&
        canEditRecord(record) &&
        source.id != destination.id &&
        _accessPolicy.canMove(
          sourceSharedWithMe: source.isSharedWithMe,
          destinationReadOnly: destination.isReadOnly,
          destinationSharedWithMe: destination.isSharedWithMe,
          privacy: record.task.privacy,
        );
  }

  List<TaskHierarchyNode> get taskTree {
    final records = _filteredRecords;
    if (isSmartView) {
      return List<TaskHierarchyNode>.unmodifiable(
        records.map(
          (record) => TaskHierarchyNode(
            task: record.task,
            children: const <TaskHierarchyNode>[],
          ),
        ),
      );
    }
    return _hierarchy.build(
      records.map((record) => record.task),
      descending: _descending,
    );
  }

  List<TaskRecord> get visibleTasks {
    if (isSmartView) {
      return List<TaskRecord>.unmodifiable(_filteredRecords);
    }
    final recordsByUid = <String, TaskRecord>{
      for (final record in _tasks) record.task.uid: record,
    };
    final flattened = <TaskRecord>[];
    void appendNodes(Iterable<TaskHierarchyNode> nodes) {
      for (final node in nodes) {
        flattened.add(recordsByUid[node.task.uid]!);
        appendNodes(node.children);
      }
    }

    appendNodes(taskTree);
    return List<TaskRecord>.unmodifiable(flattened);
  }

  TaskRecord recordForUid(String uid) {
    return _tasks.firstWhere((record) => record.task.uid == uid);
  }

  TaskRecord recordForTask(CloudTask task) {
    return _recordsByKey[_taskKey(task.calendarId, task.uid)]!;
  }

  int descendantCount(TaskRecord record) {
    return _descendantCounts[
          _taskKey(record.task.calendarId, record.task.uid)
        ] ??
        0;
  }

  List<TaskRecord> availableParentsFor(TaskRecord record) {
    final sameCalendar = _tasks.where(
      (item) => item.task.calendarId == record.task.calendarId,
    );
    final excluded = <String>{
      record.task.uid,
      ..._hierarchy.descendantUids(
        sameCalendar.map((item) => item.task),
        record.task.uid,
      ),
    };
    return List<TaskRecord>.unmodifiable(
      sameCalendar.where((item) => !excluded.contains(item.task.uid)),
    );
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      _preferences = await _taskStore.readAppPreferences();
    } on Object {
      _preferences = const CloudTasksPreferences();
    }
    _descending = _preferences.descendingManualOrder;
    _selectedCalendarId = _preferences.lastCalendarId;
    _selectedSmartView = _preferences.lastSmartView;
    _configureAutomaticSync();
    try {
      await _backgroundSyncScheduler.configure(
        _preferences.automaticSyncMinutes,
      );
    } on Object {
      // Foreground and resume synchronization remain available if Android's
      // background scheduler is unavailable on this device.
    }
    List<NextcloudAccount> accounts;
    try {
      accounts = await _accountStore.readAll();
    } on Object catch (error) {
      _message = _safeMessage(error, action: 'Reading the saved account');
      _setState(CloudTasksViewState.error);
      return;
    }
    if (accounts.isEmpty) {
      _setState(CloudTasksViewState.signedOut);
      return;
    }

    _account = accounts.first;
    try {
      await _loadCachedData();
    } on Object catch (error) {
      _message = _safeMessage(error, action: 'Opening the local task cache');
    }
    await refresh();
  }

  Future<void> connect(String serverUrl) async {
    _message = null;
    _setState(CloudTasksViewState.authenticating);
    final client = http.Client();
    NextcloudAccount account;
    try {
      final flow = LoginFlowV2(client: client, openBrowser: _browserLauncher);
      account = await flow.authenticate(serverUrl);
    } on Object catch (error) {
      _message = _safeMessage(error, action: 'Nextcloud authorization');
      _setState(CloudTasksViewState.error);
      return;
    } finally {
      client.close();
    }

    try {
      await _accountStore.save(account);
    } on Object catch (error) {
      _message = _safeMessage(
        error,
        action: 'Saving the approved app password',
      );
      _setState(CloudTasksViewState.error);
      return;
    }

    _account = account;
    await refresh();
  }

  Future<void> refresh() async {
    if (_syncInProgress) {
      return;
    }
    await _waitForLocalEdits();
    _notificationTimer?.cancel();
    _notificationTimer = null;
    await _notificationQueue;
    if (_writebackInProgress) {
      _refreshAfterWriteback = true;
      return;
    }
    final currentAccount = _account;
    if (currentAccount == null) {
      _setState(CloudTasksViewState.signedOut);
      return;
    }

    _writebackTimer?.cancel();
    _writebackTimer = null;
    _syncInProgress = true;
    _message = null;
    _setState(CloudTasksViewState.syncing);
    final authenticated = AuthenticatedClient(account: currentAccount);
    Object? synchronizationError;
    try {
      final dav = DavHttpClient(authenticated);
      final pendingWarnings = await _flushPendingWrites(dav);
      final sync = InitialSyncService(
        discovery: CalDavDiscoveryService(dav),
        taskReader: CalDavTaskReader(dav),
        store: _taskStore,
      );
      final result = await sync.synchronize(currentAccount);
      final warnings = <String>[...pendingWarnings, ...result.warnings];
      if (warnings.isNotEmpty) {
        _message = warnings.join('\n');
      }
    } on Object catch (error) {
      synchronizationError = error;
      _message = _safeMessage(error, action: 'CalDAV synchronization');
    }

    try {
      await _loadCachedData();
    } on Object catch (error) {
      final cacheMessage = _safeMessage(
        error,
        action: 'Opening the local task cache',
      );
      _message = synchronizationError == null
          ? cacheMessage
          : '${_message!}\n$cacheMessage';
      _setState(CloudTasksViewState.error);
      authenticated.close();
      _syncInProgress = false;
      return;
    }

    try {
      _setState(
        synchronizationError != null && _calendars.isEmpty
            ? CloudTasksViewState.error
            : CloudTasksViewState.ready,
      );
      await _reconcileNotifications();
      if (synchronizationError == null) {
        _lastSuccessfulSync = DateTime.now().toUtc();
      }
    } finally {
      authenticated.close();
      _syncInProgress = false;
      notifyListeners();
      if (_writebackRequested) {
        _schedulePendingWriteback(delay: Duration.zero);
      }
    }
  }

  Future<void> updatePreferences(CloudTasksPreferences preferences) async {
    const allowedIntervals = <int>{0, 15, 30, 60};
    if (!allowedIntervals.contains(preferences.automaticSyncMinutes)) {
      throw ArgumentError.value(
        preferences.automaticSyncMinutes,
        'automaticSyncMinutes',
      );
    }
    await _taskStore.saveAppPreferences(preferences);
    _preferences = preferences;
    _configureAutomaticSync();
    try {
      await _backgroundSyncScheduler.configure(
        preferences.automaticSyncMinutes,
      );
    } on Object {
      _message = 'Settings were saved, but Android could not schedule '
          'background sync. Foreground and resume sync remain available.';
    }
    notifyListeners();
  }

  void handleAppResumed() {
    if (!_preferences.syncOnResume ||
        _account == null ||
        _state != CloudTasksViewState.ready ||
        _isSaving ||
        _writebackInProgress) {
      return;
    }
    final last = _lastSuccessfulSync;
    if (last == null ||
        DateTime.now().toUtc().difference(last) >= const Duration(minutes: 1)) {
      unawaited(refresh());
    }
  }

  void _configureAutomaticSync() {
    _automaticSyncTimer?.cancel();
    _automaticSyncTimer = null;
    final minutes = _preferences.automaticSyncMinutes;
    if (minutes <= 0) return;
    _automaticSyncTimer = Timer.periodic(Duration(minutes: minutes), (_) {
      if (_account != null &&
          _state == CloudTasksViewState.ready &&
          !_isSaving &&
          !_writebackInProgress) {
        unawaited(refresh());
      }
    });
  }

  void _schedulePendingWriteback({
    Duration delay = _writebackDelay,
  }) {
    if (_disposed || _account == null) {
      return;
    }
    _writebackTimer?.cancel();
    _writebackTimer = null;
    if (_syncInProgress || _writebackInProgress) {
      _writebackRequested = true;
      return;
    }
    _writebackRequested = false;
    _writebackTimer = Timer(delay, () {
      _writebackTimer = null;
      final writeback = _flushQueuedWritesInBackground();
      _activeWriteback = writeback;
      unawaited(
        writeback.whenComplete(() {
          if (identical(_activeWriteback, writeback)) {
            _activeWriteback = null;
          }
        }),
      );
    });
  }

  Future<void> _waitForLocalEdits() async {
    while (true) {
      final pending = _localEditQueue;
      await pending;
      if (identical(pending, _localEditQueue)) {
        return;
      }
    }
  }

  Future<void> _flushQueuedWritesInBackground() async {
    if (_syncInProgress || _writebackInProgress) {
      _writebackRequested = true;
      return;
    }
    await _waitForLocalEdits();
    if (_syncInProgress || _writebackInProgress || _disposed) {
      _writebackRequested = true;
      return;
    }
    final currentAccount = _account;
    if (currentAccount == null) {
      return;
    }

    _writebackRequested = false;
    _writebackInProgress = true;
    _writebackPreparing = true;
    notifyListeners();
    final authenticated = AuthenticatedClient(account: currentAccount);
    try {
      final warnings = await _flushPendingWrites(
        DavHttpClient(authenticated),
      );
      _message = warnings.isEmpty ? null : warnings.join('\n');
      await _loadCachedData();
    } on Object catch (error) {
      _message = _safeMessage(error, action: 'Synchronizing saved changes');
    } finally {
      authenticated.close();
      _writebackPreparing = false;
      _writebackInProgress = false;
      notifyListeners();
    }

    if (_refreshAfterWriteback) {
      _refreshAfterWriteback = false;
      unawaited(refresh());
    } else if (_writebackRequested) {
      _schedulePendingWriteback(delay: Duration.zero);
    }
  }

  Future<void> selectCalendar(String calendarId) async {
    if (!_calendarsById.containsKey(calendarId)) {
      return;
    }
    final generation = ++_viewSelectionGeneration;
    _selectedSmartView = null;
    _selectedCalendarId = calendarId;
    _preferences = _preferences.copyWith(
      lastCalendarId: calendarId,
      clearLastSmartView: true,
    );
    await _saveViewPreferences();
    List<TaskRecord> records;
    try {
      records = await _taskStore.readCalendarTasks(calendarId);
    } on Object catch (error) {
      if (generation == _viewSelectionGeneration) {
        _replaceTasks(const <TaskRecord>[]);
        _message = _safeMessage(error, action: 'Opening the selected list');
        notifyListeners();
      }
      return;
    }
    if (generation != _viewSelectionGeneration) {
      return;
    }
    _replaceTasks(records);
    notifyListeners();
  }

  Future<void> selectSmartView(SmartTaskView view) async {
    final generation = ++_viewSelectionGeneration;
    _selectedSmartView = view;
    _preferences = _preferences.copyWith(lastSmartView: view);
    await _saveViewPreferences();
    final records = <TaskRecord>[];
    try {
      for (final calendar in _calendars) {
        records.addAll(await _taskStore.readCalendarTasks(calendar.id));
      }
    } on Object catch (error) {
      if (generation == _viewSelectionGeneration) {
        _replaceTasks(const <TaskRecord>[]);
        _message = _safeMessage(error, action: 'Opening the selected view');
        notifyListeners();
      }
      return;
    }
    if (generation != _viewSelectionGeneration) {
      return;
    }
    _replaceTasks(records);
    notifyListeners();
  }

  void setSearchQuery(String value) {
    final normalized = value.trimLeft();
    if (_searchQuery == normalized) {
      return;
    }
    _searchQuery = normalized;
    notifyListeners();
  }

  void setFilters({required String query, String? tag}) {
    final normalizedQuery = query.trimLeft();
    if (_searchQuery == normalizedQuery && _selectedTag == tag) {
      return;
    }
    _searchQuery = normalizedQuery;
    _selectedTag = tag;
    notifyListeners();
  }

  void clearFilters() => setFilters(query: '');

  void selectTag(String? tag) {
    _selectedTag = tag;
    notifyListeners();
  }

  Future<void> setDefaultCalendar(TaskCalendar calendar) async {
    final account = _account;
    if (account == null || calendar.isReadOnly || _isSaving) {
      return;
    }
    await _taskStore.setDefaultCalendarId(account.id, calendar.id);
    _defaultCalendarId = calendar.id;
    notifyListeners();
  }

  Future<List<CalendarShare>> loadCalendarShares(TaskCalendar calendar) async {
    final account = _account;
    if (account == null || !canShareCalendar(calendar)) {
      throw const CalendarSharingException(
        'This task list cannot be shared by the current account.',
      );
    }
    final authenticated = AuthenticatedClient(account: account);
    try {
      return await CalDavCalendarSharingService(DavHttpClient(authenticated))
          .readShares(calendar);
    } finally {
      authenticated.close();
    }
  }

  Future<bool> shareCalendar({
    required TaskCalendar calendar,
    required String recipientId,
    required CalendarShareKind kind,
    required bool canWrite,
  }) async {
    return _changeCalendarShare(
      calendar,
      (service) => service.share(
        calendar: calendar,
        recipientId: recipientId,
        kind: kind,
        canWrite: canWrite,
      ),
      action: 'Sharing the task list',
    );
  }

  Future<bool> updateCalendarSharePermission({
    required TaskCalendar calendar,
    required CalendarShare share,
    required bool canWrite,
  }) async {
    return _changeCalendarShare(
      calendar,
      (service) => service.updatePermission(
        calendar: calendar,
        share: share,
        canWrite: canWrite,
      ),
      action: 'Changing sharing permission',
    );
  }

  Future<bool> removeCalendarShare({
    required TaskCalendar calendar,
    required CalendarShare share,
  }) async {
    return _changeCalendarShare(
      calendar,
      (service) => service.unshare(calendar: calendar, share: share),
      action: 'Removing the share',
    );
  }

  Future<bool> _changeCalendarShare(
    TaskCalendar calendar,
    Future<void> Function(CalDavCalendarSharingService service) change, {
    required String action,
  }) async {
    final account = _account;
    if (account == null || !canShareCalendar(calendar)) {
      return false;
    }
    _isSaving = true;
    _message = null;
    notifyListeners();
    final authenticated = AuthenticatedClient(account: account);
    try {
      await change(CalDavCalendarSharingService(DavHttpClient(authenticated)));
      return true;
    } on Object catch (error) {
      _message = _safeMessage(error, action: action);
      return false;
    } finally {
      authenticated.close();
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> setSortDirection(bool descending) async {
    if (_descending == descending) {
      return;
    }
    _descending = descending;
    _preferences = _preferences.copyWith(descendingManualOrder: descending);
    notifyListeners();
    await _saveViewPreferences();
  }

  Future<void> toggleDirection() => setSortDirection(!_descending);

  void clearMessage() {
    if (_message == null) {
      return;
    }
    _message = null;
    notifyListeners();
  }

  Future<void> createCalendar({
    required String displayName,
    required String color,
  }) async {
    final account = _account;
    final normalizedName = displayName.trim();
    if (account == null ||
        normalizedName.isEmpty ||
        state != CloudTasksViewState.ready ||
        _isSaving) {
      return;
    }
    _isSaving = true;
    _message = null;
    notifyListeners();
    final authenticated = AuthenticatedClient(account: account);
    var succeeded = false;
    try {
      final dav = DavHttpClient(authenticated);
      final discovered = await CalDavDiscoveryService(dav).discover(account);
      final sortOrder = _calendars.isEmpty
          ? ManualOrderService.spacing
          : (_calendars.last.sortOrder ??
                  _calendars.length * ManualOrderService.spacing) +
              ManualOrderService.spacing;
      final created = await CalDavCalendarWriter(dav).create(
        accountId: account.id,
        calendarHomeUrl: discovered.calendarHomeUrl,
        collectionId: _newUid(),
        displayName: normalizedName,
        color: color,
        sortOrder: sortOrder,
      );
      await _taskStore.saveCalendars(<TaskCalendar>[created]);
      if (_defaultCalendarId == null) {
        await _taskStore.setDefaultCalendarId(account.id, created.id);
        _defaultCalendarId = created.id;
      }
      _selectedCalendarId = created.id;
      _selectedSmartView = null;
      succeeded = true;
    } on Object catch (error) {
      _message = _safeMessage(error, action: 'Creating the task list');
    } finally {
      authenticated.close();
      _isSaving = false;
      notifyListeners();
    }
    if (succeeded) {
      await refresh();
    }
  }

  Future<void> updateCalendar(
    TaskCalendar calendar, {
    required String displayName,
    required String color,
  }) async {
    final account = _account;
    final normalizedName = displayName.trim();
    if (account == null ||
        !canManageCalendar(calendar) ||
        normalizedName.isEmpty ||
        state != CloudTasksViewState.ready ||
        _isSaving) {
      return;
    }
    _isSaving = true;
    _message = null;
    notifyListeners();
    final authenticated = AuthenticatedClient(account: account);
    var succeeded = false;
    try {
      await CalDavCalendarWriter(DavHttpClient(authenticated)).update(
        calendar,
        displayName: normalizedName,
        color: color,
        sortOrder: calendar.sortOrder ?? ManualOrderService.spacing,
      );
      succeeded = true;
    } on Object catch (error) {
      _message = _safeMessage(error, action: 'Updating the task list');
    } finally {
      authenticated.close();
      _isSaving = false;
      notifyListeners();
    }
    if (succeeded) {
      await refresh();
    }
  }

  Future<void> deleteCalendar(TaskCalendar calendar) async {
    final account = _account;
    if (account == null ||
        (!calendar.isSharedWithMe && !canManageCalendar(calendar)) ||
        state != CloudTasksViewState.ready ||
        _isSaving) {
      return;
    }
    _isSaving = true;
    _message = null;
    notifyListeners();
    final authenticated = AuthenticatedClient(account: account);
    var succeeded = false;
    try {
      await CalDavCalendarWriter(DavHttpClient(authenticated)).delete(calendar);
      succeeded = true;
    } on Object catch (error) {
      _message = _safeMessage(
        error,
        action: calendar.isSharedWithMe
            ? 'Removing the shared task list'
            : 'Deleting the task list',
      );
    } finally {
      authenticated.close();
      _isSaving = false;
      notifyListeners();
    }
    if (succeeded) {
      if (_defaultCalendarId == calendar.id) {
        await _taskStore.setDefaultCalendarId(account.id, null);
        _defaultCalendarId = null;
      }
      if (_selectedCalendarId == calendar.id) {
        _selectedCalendarId = null;
      }
      await refresh();
    }
  }

  Future<void> reorderCalendars(int oldIndex, int newIndex) async {
    final account = _account;
    if (account == null ||
        oldIndex < 0 ||
        oldIndex >= _calendars.length ||
        newIndex < 0 ||
        newIndex > _calendars.length ||
        state != CloudTasksViewState.ready ||
        _isSaving) {
      return;
    }
    final reordered = List<TaskCalendar>.of(_calendars);
    final moved = reordered.removeAt(oldIndex);
    var insertionIndex = newIndex;
    if (insertionIndex > oldIndex) {
      insertionIndex--;
    }
    reordered.insert(insertionIndex, moved);
    if (reordered.indexWhere((item) => item.id == moved.id) == oldIndex) {
      return;
    }
    if (reordered.any((calendar) => !canManageCalendar(calendar))) {
      _message = 'Shared or read-only lists prevent changing the global list '
          'order on this account.';
      notifyListeners();
      return;
    }

    _isSaving = true;
    _message = null;
    _replaceCalendars(reordered);
    notifyListeners();
    final authenticated = AuthenticatedClient(account: account);
    var succeeded = false;
    try {
      final writer = CalDavCalendarWriter(DavHttpClient(authenticated));
      for (var index = 0; index < reordered.length; index++) {
        final calendar = reordered[index];
        final order = (index + 1) * ManualOrderService.spacing;
        if (calendar.sortOrder == order) {
          continue;
        }
        await writer.update(
          calendar,
          displayName: calendar.displayName,
          color: calendar.color ?? '#0082C9',
          sortOrder: order,
        );
      }
      succeeded = true;
    } on Object catch (error) {
      _message = _safeMessage(error, action: 'Reordering task lists');
    } finally {
      authenticated.close();
      _isSaving = false;
      notifyListeners();
    }
    if (succeeded) {
      await refresh();
    } else {
      await _loadCachedData();
      notifyListeners();
    }
  }

  Future<void> updateSummary(TaskRecord record, String summary) async {
    final normalized = summary.trim();
    if (normalized.isEmpty || normalized == record.task.summary) {
      return;
    }
    final document = _codec.writeSummaryAndStamp(
      record.rawDocument,
      normalized,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'SUMMARY'}),
    ]);
  }

  Future<void> createTask(
    String summary, {
    String? parentUid,
    String? calendarId,
  }) async {
    await createTasks(
      <String>[summary],
      parentUid: parentUid,
      calendarId: calendarId,
    );
  }

  Future<void> createTasks(
    Iterable<String> summaries, {
    String? parentUid,
    String? calendarId,
  }) async {
    final normalizedSummaries = summaries
        .map((summary) => summary.trim())
        .where((summary) => summary.isNotEmpty)
        .toList(growable: false);
    TaskCalendar? calendar = taskCreationCalendar;
    if (calendarId != null) {
      calendar = null;
      for (final candidate in _calendars) {
        if (candidate.id == calendarId) {
          calendar = candidate;
          break;
        }
      }
    }
    if (normalizedSummaries.isEmpty ||
        calendar == null ||
        calendar.isReadOnly ||
        state != CloudTasksViewState.ready ||
        _isSaving) {
      return;
    }
    final targetCalendar = calendar;
    final now = DateTime.now().toUtc();
    if (parentUid != null &&
        !_tasks.any(
          (record) =>
              record.task.uid == parentUid &&
              record.task.calendarId == targetCalendar.id,
        )) {
      return;
    }
    final siblings = _recordsForParent(
      parentUid,
      calendarId: targetCalendar.id,
    );
    final newTasks = <CloudTask>[
      for (final summary in normalizedSummaries)
        CloudTask(
          uid: _newUid(),
          summary: summary,
          calendarId: targetCalendar.id,
          parentUid: parentUid,
        ),
    ];
    final currentDisplay = _ordering.sort(
      siblings.map((record) => record.task),
      descending: _descending,
    );
    final desiredDisplay = <CloudTask>[...newTasks, ...currentDisplay];
    final ordered = _ordering.reindex(
      _descending ? desiredDisplay.reversed : desiredDisplay,
    );
    final newByUid = <String, CloudTask>{
      for (final task in newTasks) task.uid: task,
    };
    final recordsByUid = <String, TaskRecord>{
      for (final record in _tasks.where(
        (item) => item.task.calendarId == targetCalendar.id,
      ))
        record.task.uid: record,
    };
    final edits = <LocalTaskEdit>[];
    for (final task in ordered) {
      final newTask = newByUid[task.uid];
      if (newTask != null) {
        final document = _codec.create(
          uid: task.uid,
          summary: newTask.summary,
          sortOrder: task.sortOrder!,
          now: now,
          parentUid: parentUid,
        );
        edits.add(
          LocalTaskEdit(
            record: TaskRecord(
              task: _codec.decode(document, calendarId: targetCalendar.id),
              href: _taskHref(targetCalendar.href, task.uid),
              rawDocument: document,
              isDirty: true,
            ),
            operation: PendingTaskOperation.create(
              taskUid: task.uid,
              calendarId: targetCalendar.id,
            ),
          ),
        );
        continue;
      }
      final original = recordsByUid[task.uid]!;
      if (task.sortOrder == original.task.sortOrder) {
        continue;
      }
      final reorderedDocument = _codec.writeManualOrderAndStamp(
        original.rawDocument,
        task.sortOrder!,
        now: now,
      );
      edits.add(
        _localEdit(original, reorderedDocument, const <String>{
          'X-APPLE-SORT-ORDER',
        }),
      );
    }
    await _saveEdits(edits);
  }

  Future<void> duplicateTaskTree(TaskRecord record) async {
    final calendarId = record.task.calendarId;
    final calendar = calendarForRecord(record);
    if (calendarId == null ||
        calendar == null ||
        calendar.isReadOnly ||
        !canEditRecord(record)) {
      return;
    }
    final allRecords = await _taskStore.readCalendarTasks(calendarId);
    final sourceUids = <String>{
      record.task.uid,
      ..._hierarchy.descendantUids(
        allRecords.map((item) => item.task),
        record.task.uid,
      ),
    };
    final source = allRecords
        .where((item) => sourceUids.contains(item.task.uid))
        .toList(growable: false);
    final uidMap = <String, String>{
      for (final item in source) item.task.uid: _newUid(),
    };
    final rootUid = uidMap[record.task.uid]!;
    final rootPlaceholder = record.task.copyWith(uid: rootUid);
    final siblings = _recordsForParent(
      record.task.parentUid,
      calendarId: calendarId,
    );
    final positioned = _ordering.insertDisplayed(
      _ordering.sort(
        siblings.map((item) => item.task),
        descending: _descending,
      ),
      rootPlaceholder,
      descending: _descending,
    );
    final positionByUid = <String, int>{
      for (final task in positioned) task.uid: task.sortOrder!,
    };
    final recordsByUid = <String, TaskRecord>{
      for (final item in allRecords) item.task.uid: item,
    };
    final now = DateTime.now().toUtc();
    final edits = <LocalTaskEdit>[];
    for (final task in positioned) {
      if (task.uid == rootUid) {
        continue;
      }
      final original = recordsByUid[task.uid]!;
      if (original.task.sortOrder != task.sortOrder) {
        edits.add(
          _localEdit(
            original,
            _codec.writeManualOrderAndStamp(
              original.rawDocument,
              task.sortOrder!,
              now: now,
            ),
            const <String>{'X-APPLE-SORT-ORDER'},
          ),
        );
      }
    }
    for (final item in source) {
      final isRoot = item.task.uid == record.task.uid;
      final newUid = uidMap[item.task.uid]!;
      final parentUid =
          isRoot ? item.task.parentUid : uidMap[item.task.parentUid];
      final document = _codec.duplicate(
        item.rawDocument,
        uid: newUid,
        parentUid: parentUid,
        sortOrder: isRoot
            ? positionByUid[rootUid]!
            : item.task.sortOrder ?? ManualOrderService.spacing,
        now: now,
      );
      edits.add(
        LocalTaskEdit(
          record: TaskRecord(
            task: _codec.decode(document, calendarId: calendarId),
            href: _taskHref(calendar.href, newUid),
            rawDocument: document,
            isDirty: true,
          ),
          operation: PendingTaskOperation.create(
            taskUid: newUid,
            calendarId: calendarId,
          ),
        ),
      );
    }
    await _saveEdits(edits);
  }

  Future<void> updateDescription(TaskRecord record, String description) async {
    final normalized = description.trim();
    if (normalized == (record.task.description ?? '').trim()) {
      return;
    }
    final document = _codec.writeDescriptionAndStamp(
      record.rawDocument,
      normalized,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'DESCRIPTION'}),
    ]);
  }

  Future<void> updateTaskDate(
    TaskRecord record,
    String propertyName,
    CloudTaskDate? date,
  ) async {
    final document = _codec.writeTaskDateAndStamp(
      record.rawDocument,
      propertyName,
      date,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, <String>{propertyName.toUpperCase()}),
    ]);
  }

  Future<void> updatePriority(TaskRecord record, int? priority) async {
    if (priority == record.task.priority) {
      return;
    }
    final document = _codec.writePriorityAndStamp(
      record.rawDocument,
      priority,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'PRIORITY'}),
    ]);
  }

  Future<void> updateCategories(
    TaskRecord record,
    Iterable<String> categories,
  ) async {
    final normalized = categories
        .map((category) => category.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (listEquals(normalized, record.task.categories)) {
      return;
    }
    final document = _codec.writeCategoriesAndStamp(
      record.rawDocument,
      normalized,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'CATEGORIES'}),
    ]);
  }

  Future<void> updatePrivacy(
    TaskRecord record,
    CloudTaskPrivacy? privacy,
  ) async {
    if (privacy == record.task.privacy || !canEditPrivacy(record)) {
      return;
    }
    final document = _codec.writePrivacyAndStamp(
      record.rawDocument,
      privacy,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'CLASS'}),
    ]);
  }

  Future<void> updatePinned(TaskRecord record, bool pinned) async {
    if (pinned == record.task.pinned || !canEditRecord(record)) {
      return;
    }
    final document = _codec.writePinnedAndStamp(
      record.rawDocument,
      pinned,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'X-PINNED'}),
    ]);
  }

  String exportCalendar(TaskCalendar calendar) {
    final records = _tasks
        .where((record) => record.task.calendarId == calendar.id)
        .map((record) => record.rawDocument);
    return _archive.encode(records);
  }

  Future<int> importTasks(String source, {required String calendarId}) async {
    TaskCalendar? calendar;
    for (final candidate in _calendars) {
      if (candidate.id == calendarId) {
        calendar = candidate;
        break;
      }
    }
    if (calendar == null || calendar.isReadOnly || _isSaving) {
      return 0;
    }
    final documents = _archive.decode(source);
    final decoded = <({ICalendarDocument document, CloudTask task})>[];
    for (final document in documents) {
      decoded.add((document: document, task: _codec.decode(document)));
    }
    final uidMap = <String, String>{
      for (final item in decoded) item.task.uid: _newUid(),
    };
    final roots = decoded
        .where(
          (item) =>
              item.task.parentUid == null ||
              !uidMap.containsKey(item.task.parentUid),
        )
        .toList(growable: false);
    final existingRoots = _recordsForParent(null, calendarId: calendarId);
    final rootPlaceholders = <CloudTask>[
      for (final item in roots)
        item.task.copyWith(
          uid: uidMap[item.task.uid],
          calendarId: calendarId,
          clearParentUid: true,
        ),
    ];
    final desiredAscending = <CloudTask>[
      ..._ordering.sort(existingRoots.map((item) => item.task)),
      ...rootPlaceholders,
    ];
    final positionedRoots = _ordering.reindex(desiredAscending);
    final rootPositions = <String, int>{
      for (final task in positionedRoots) task.uid: task.sortOrder!,
    };
    final existingByUid = <String, TaskRecord>{
      for (final item in existingRoots) item.task.uid: item,
    };
    final now = DateTime.now().toUtc();
    final edits = <LocalTaskEdit>[];
    for (final task in positionedRoots) {
      final original = existingByUid[task.uid];
      if (original != null && original.task.sortOrder != task.sortOrder) {
        edits.add(
          _localEdit(
            original,
            _codec.writeManualOrderAndStamp(
              original.rawDocument,
              task.sortOrder!,
              now: now,
            ),
            const <String>{'X-APPLE-SORT-ORDER'},
          ),
        );
      }
    }
    for (final item in decoded) {
      final newUid = uidMap[item.task.uid]!;
      final mappedParent = uidMap[item.task.parentUid];
      final isRoot = mappedParent == null;
      final document = _codec.duplicate(
        item.document,
        uid: newUid,
        parentUid: mappedParent,
        sortOrder: isRoot
            ? rootPositions[newUid]!
            : item.task.sortOrder ?? ManualOrderService.spacing,
        now: now,
        resetCompletion: false,
        resetCreated: false,
      );
      edits.add(
        LocalTaskEdit(
          record: TaskRecord(
            task: _codec.decode(document, calendarId: calendarId),
            href: _taskHref(calendar.href, newUid),
            rawDocument: document,
            isDirty: true,
          ),
          operation: PendingTaskOperation.create(
            taskUid: newUid,
            calendarId: calendarId,
          ),
        ),
      );
    }
    await _saveEdits(edits);
    return decoded.length;
  }

  Future<void> deleteCompletedTasks() async {
    final calendar = selectedCalendar;
    if (calendar == null || calendar.isReadOnly) {
      return;
    }
    final records = await _taskStore.readCalendarTasks(calendar.id);
    final deleteUids = <String>{};
    for (final item in records.where(
      (item) => item.task.isCompleted,
    )) {
      deleteUids
        ..add(item.task.uid)
        ..addAll(
          _hierarchy.descendantUids(
            records.map((record) => record.task),
            item.task.uid,
          ),
        );
    }
    if (deleteUids.isEmpty) {
      return;
    }
    await _saveEdits(<LocalTaskEdit>[
      for (final item in records.where(
        (item) => deleteUids.contains(item.task.uid),
      ))
        LocalTaskEdit(
          record: item.copyWith(isDirty: true),
          operation: PendingTaskOperation.delete(
            taskUid: item.task.uid,
            calendarId: calendar.id,
          ),
        ),
    ]);
  }

  Future<int> restoreCompletedTasks() async {
    final calendar = selectedCalendar;
    if (calendar == null || !canRestoreCompletedTasks) {
      return 0;
    }
    final records = await _taskStore.readCalendarTasks(calendar.id);
    final completed = records
        .where((record) => record.task.isCompleted && canEditRecord(record))
        .toList(growable: false);
    if (completed.isEmpty) {
      return 0;
    }
    final now = DateTime.now().toUtc();
    final saved = await _saveEdits(<LocalTaskEdit>[
      for (final record in completed)
        _localEdit(
          record,
          _codec.writeCompletion(
            record.rawDocument,
            isCompleted: false,
            now: now,
          ),
          const <String>{
            'STATUS',
            'PERCENT-COMPLETE',
            'COMPLETED',
          },
        ),
    ]);
    return saved ? completed.length : 0;
  }

  Future<void> updateLocation(TaskRecord record, String location) async {
    if (location.trim() == (record.task.location ?? '').trim()) {
      return;
    }
    final document = _codec.writeTextPropertyAndStamp(
      record.rawDocument,
      'LOCATION',
      location,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'LOCATION'}),
    ]);
  }

  Future<void> updateUrl(TaskRecord record, String url) async {
    final normalized = url.trim();
    if (normalized == (record.task.url?.toString() ?? '')) {
      return;
    }
    final document = _codec.writeUrlAndStamp(
      record.rawDocument,
      normalized,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'URL'}),
    ]);
  }

  Future<void> updateRecurrence(
    TaskRecord record,
    String? recurrenceRule,
  ) async {
    if ((recurrenceRule ?? '') == (record.task.recurrenceRule ?? '')) {
      return;
    }
    final document = _codec.writeRecurrenceAndStamp(
      record.rawDocument,
      recurrenceRule,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'RRULE'}),
    ]);
  }

  Future<void> updateReminder(TaskRecord record, Duration? beforeDue) async {
    final document = _codec.writeReminderAndStamp(
      record.rawDocument,
      beforeDue,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'VALARM'}),
    ]);
  }

  Future<void> updateReminders(
    TaskRecord record,
    Iterable<CloudTaskReminder> reminders,
  ) async {
    final document = _codec.writeRemindersAndStamp(
      record.rawDocument,
      reminders,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{'VALARM'}),
    ]);
  }

  Future<void> updateStatus(TaskRecord record, CloudTaskStatus? status) async {
    if (record.task.status == status) {
      return;
    }
    if (status == CloudTaskStatus.completed &&
        record.task.recurrenceRule != null) {
      await _completeRecurringTask(record);
      return;
    }
    final document = _codec.writeStatusAndProgress(
      record.rawDocument,
      status: status,
      percentComplete: record.task.percentComplete ?? 0,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{
        'STATUS',
        'PERCENT-COMPLETE',
        'COMPLETED',
      }),
    ]);
  }

  Future<void> updateCompletedAt(
    TaskRecord record,
    DateTime? completedAt,
  ) async {
    final now = DateTime.now().toUtc();
    final normalized = completedAt?.toUtc();
    if (normalized != null && normalized.isAfter(now)) {
      _message = 'Completion date must not be in the future.';
      notifyListeners();
      return;
    }
    if (record.task.completedAt == normalized) {
      return;
    }
    final document = _codec.writeCompletedAtAndStamp(
      record.rawDocument,
      normalized,
      now: now,
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{
        'STATUS',
        'PERCENT-COMPLETE',
        'COMPLETED',
      }),
    ]);
  }

  Future<void> updateProgress(TaskRecord record, int percentComplete) async {
    if (record.task.percentComplete == percentComplete) {
      return;
    }
    if (percentComplete == 100 && record.task.recurrenceRule != null) {
      await _completeRecurringTask(record);
      return;
    }
    final document = _codec.writeProgressAndStamp(
      record.rawDocument,
      percentComplete,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{
        'STATUS',
        'PERCENT-COMPLETE',
        'COMPLETED',
      }),
    ]);
  }

  Future<void> deleteTask(TaskRecord record) async {
    await deleteTaskTree(record);
  }

  Future<void> deleteTaskTree(TaskRecord record) async {
    final calendarId = record.task.calendarId;
    if (calendarId == null || !canEditRecord(record)) {
      return;
    }
    final calendarRecords = await _taskStore.readCalendarTasks(calendarId);
    final deleteUids = <String>{
      record.task.uid,
      ..._hierarchy.descendantUids(
        calendarRecords.map((item) => item.task),
        record.task.uid,
      ),
    };
    await _saveEdits(<LocalTaskEdit>[
      for (final item in calendarRecords.where(
        (candidate) => deleteUids.contains(candidate.task.uid),
      ))
        LocalTaskEdit(
          record: item.copyWith(isDirty: true),
          operation: PendingTaskOperation.delete(
            taskUid: item.task.uid,
            calendarId: calendarId,
          ),
        ),
    ]);
  }

  Future<void> moveTaskTree(
    TaskRecord record,
    String destinationCalendarId,
  ) async {
    final sourceCalendarId = record.task.calendarId;
    TaskCalendar? destination;
    for (final calendar in _calendars) {
      if (calendar.id == destinationCalendarId) {
        destination = calendar;
        break;
      }
    }
    if (sourceCalendarId == null ||
        sourceCalendarId == destinationCalendarId ||
        destination == null ||
        !canMoveRecordTo(record, destination)) {
      return;
    }

    final sourceRecords = await _taskStore.readCalendarTasks(sourceCalendarId);
    final destinationRecords = await _taskStore.readCalendarTasks(
      destinationCalendarId,
    );
    final movingUids = <String>{
      record.task.uid,
      ..._hierarchy.descendantUids(
        sourceRecords.map((item) => item.task),
        record.task.uid,
      ),
    };
    final movingRecords = sourceRecords
        .where((item) => movingUids.contains(item.task.uid))
        .toList(growable: false);
    if (destinationRecords.any((item) => movingUids.contains(item.task.uid))) {
      _message = 'The destination already contains one of this task’s IDs. '
          'Nothing was moved.';
      notifyListeners();
      return;
    }
    final destinationRoots = destinationRecords
        .where((item) => item.task.parentUid == null)
        .toList(growable: false);
    final positioned = _ordering.insertDisplayed(
      _ordering.sort(
        destinationRoots.map((item) => item.task),
        descending: _descending,
      ),
      record.task.copyWith(
        calendarId: destinationCalendarId,
        clearParentUid: true,
      ),
      descending: _descending,
    );
    final positionedByUid = <String, CloudTask>{
      for (final task in positioned) task.uid: task,
    };
    final destinationByUid = <String, TaskRecord>{
      for (final item in destinationRecords) item.task.uid: item,
    };
    final now = DateTime.now().toUtc();
    final createTime = now;
    final deleteTime = now.add(const Duration(seconds: 1));
    final moveBatchId = 'move:${_newUid()}';
    final edits = <LocalTaskEdit>[];

    for (final task in positioned) {
      if (task.uid == record.task.uid) {
        continue;
      }
      final original = destinationByUid[task.uid]!;
      if (task.sortOrder == original.task.sortOrder) {
        continue;
      }
      final document = _codec.writeManualOrderAndStamp(
        original.rawDocument,
        task.sortOrder!,
        now: now,
      );
      edits.add(
        _localEdit(original, document, const <String>{'X-APPLE-SORT-ORDER'}),
      );
    }

    for (final item in movingRecords) {
      var document = item.rawDocument;
      if (item.task.uid == record.task.uid) {
        document = _codec.writeParentAndOrderAndStamp(
          document,
          parentUid: null,
          sortOrder: positionedByUid[item.task.uid]!.sortOrder!,
          now: now,
        );
      }
      edits.add(
        LocalTaskEdit(
          record: TaskRecord(
            task: _codec.decode(document, calendarId: destinationCalendarId),
            href: _taskHref(destination.href, item.task.uid),
            rawDocument: document,
            isDirty: true,
          ),
          operation: PendingTaskOperation.create(
            taskUid: item.task.uid,
            calendarId: destinationCalendarId,
            createdAt: createTime,
            batchId: moveBatchId,
            batchPhase: 0,
          ),
        ),
      );
    }
    for (final item in movingRecords) {
      edits.add(
        LocalTaskEdit(
          record: item.copyWith(isDirty: true),
          operation: PendingTaskOperation.delete(
            taskUid: item.task.uid,
            calendarId: sourceCalendarId,
            createdAt: deleteTime,
            batchId: moveBatchId,
            batchPhase: 1,
          ),
        ),
      );
    }
    await _saveEdits(edits);
  }

  Future<void> toggleCompletion(TaskRecord record) async {
    final isCompleted = record.task.isCompleted;
    if (!isCompleted && record.task.recurrenceRule != null) {
      await _completeRecurringTask(record);
      return;
    }
    final document = _codec.writeCompletion(
      record.rawDocument,
      isCompleted: !isCompleted,
      now: DateTime.now().toUtc(),
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, document, const <String>{
        'STATUS',
        'PERCENT-COMPLETE',
        'COMPLETED',
      }),
    ]);
  }

  Future<void> _completeRecurringTask(TaskRecord record) async {
    final advance = _recurrence.nextOccurrence(record.task);
    if (advance == null) {
      final now = DateTime.now().toUtc();
      var completed = _codec.writeCompletion(
        record.rawDocument,
        isCompleted: true,
        now: now,
      );
      completed = _codec.writeRecurrenceAndStamp(completed, null, now: now);
      completed = _codec.writeRemindersAndStamp(
        completed,
        const <CloudTaskReminder>[],
        now: now,
      );
      await _saveEdits(<LocalTaskEdit>[
        _localEdit(record, completed, const <String>{
          'STATUS',
          'PERCENT-COMPLETE',
          'COMPLETED',
          'RRULE',
          'VALARM',
        }),
      ]);
      return;
    }

    final calendarId = record.task.calendarId;
    final calendar = calendarForRecord(record);
    if (calendarId == null || calendar == null || calendar.id != calendarId) {
      return;
    }
    final now = DateTime.now().toUtc();
    var completed = _codec.writeCompletion(
      record.rawDocument,
      isCompleted: true,
      now: now,
    );
    completed = _codec.writeRecurrenceAndStamp(completed, null, now: now);
    completed = _codec.writeRemindersAndStamp(
      completed,
      const <CloudTaskReminder>[],
      now: now,
    );

    final uid = _newUid();
    final nextDocument = _codec.createNextOccurrence(
      record.rawDocument,
      uid: uid,
      start: advance.start,
      due: advance.due,
      recurrenceRule: advance.recurrenceRule,
      now: now,
    );
    await _saveEdits(<LocalTaskEdit>[
      _localEdit(record, completed, const <String>{
        'STATUS',
        'PERCENT-COMPLETE',
        'COMPLETED',
        'RRULE',
        'VALARM',
      }),
      LocalTaskEdit(
        record: TaskRecord(
          task: _codec.decode(nextDocument, calendarId: calendarId),
          href: _taskHref(calendar.href, uid),
          rawDocument: nextDocument,
          isDirty: true,
        ),
        operation: PendingTaskOperation.create(
          taskUid: uid,
          calendarId: calendarId,
        ),
      ),
    ]);
  }

  Future<void> reorderVisibleTasks(int oldIndex, int newIndex) async {
    await reorderTaskGroup(
      parentUid: null,
      displayedUids: taskTree.map((node) => node.task.uid).toList(),
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  Future<void> reorderTaskGroup({
    required String? parentUid,
    required List<String> displayedUids,
    required int oldIndex,
    required int newIndex,
  }) async {
    if (!canReorderSelectedView ||
        oldIndex < 0 ||
        oldIndex >= displayedUids.length ||
        newIndex < 0 ||
        newIndex > displayedUids.length) {
      return;
    }
    final siblings = _recordsForParent(
      parentUid,
      calendarId: _selectedCalendarId,
    );
    final reordered = _ordering.reorderDisplayedSubset(
      siblings.map((record) => record.task).toList(growable: false),
      displayedUids,
      oldIndex,
      newIndex,
      descending: _descending,
    );
    final recordsByUid = <String, TaskRecord>{
      for (final record in siblings) record.task.uid: record,
    };
    final now = DateTime.now().toUtc();
    final edits = <LocalTaskEdit>[];
    for (final task in reordered) {
      final original = recordsByUid[task.uid]!;
      final parentChanged = original.task.parentUid != parentUid;
      if (task.sortOrder == original.task.sortOrder && !parentChanged) {
        continue;
      }
      final document = _codec.writeParentAndOrderAndStamp(
        original.rawDocument,
        parentUid: parentUid,
        sortOrder: task.sortOrder!,
        now: now,
      );
      edits.add(
        _localEdit(original, document, <String>{
          'X-APPLE-SORT-ORDER',
          if (parentChanged) 'RELATED-TO',
        }),
      );
    }
    await _saveEdits(edits);
  }

  Future<void> reparentTask(TaskRecord record, String? parentUid) async {
    if (!canEditRecord(record) || record.task.parentUid == parentUid) {
      return;
    }
    final sameCalendar = _tasks.where(
      (item) => item.task.calendarId == record.task.calendarId,
    );
    final disallowed = <String>{
      record.task.uid,
      ..._hierarchy.descendantUids(
        sameCalendar.map((item) => item.task),
        record.task.uid,
      ),
    };
    if (parentUid != null && disallowed.contains(parentUid)) {
      return;
    }
    final destination = _recordsForParent(
      parentUid,
      calendarId: record.task.calendarId,
    ).where((item) => item.task.uid != record.task.uid).toList(growable: false);
    final positioned = _ordering.insertDisplayed(
      destination.map((item) => item.task).toList(growable: false),
      record.task.copyWith(
        parentUid: parentUid,
        clearParentUid: parentUid == null,
      ),
      descending: _descending,
    );
    final recordsByUid = <String, TaskRecord>{
      for (final item in sameCalendar) item.task.uid: item,
    };
    final now = DateTime.now().toUtc();
    final edits = <LocalTaskEdit>[];
    for (final task in positioned) {
      final original = recordsByUid[task.uid]!;
      final parentChanged = original.task.parentUid != parentUid;
      if (task.sortOrder == original.task.sortOrder && !parentChanged) {
        continue;
      }
      final document = _codec.writeParentAndOrderAndStamp(
        original.rawDocument,
        parentUid: parentUid,
        sortOrder: task.sortOrder!,
        now: now,
      );
      edits.add(
        _localEdit(original, document, <String>{
          'X-APPLE-SORT-ORDER',
          if (parentChanged) 'RELATED-TO',
        }),
      );
    }
    await _saveEdits(edits);
  }

  Future<void> disconnect() async {
    _writebackTimer?.cancel();
    _writebackTimer = null;
    await _waitForLocalEdits();
    final activeWriteback = _activeWriteback;
    if (activeWriteback != null) {
      await activeWriteback;
    }
    final currentAccount = _account;
    if (currentAccount != null) {
      await _accountStore.delete(currentAccount.id);
      await _taskStore.clearAccount(currentAccount.id);
    }
    _account = null;
    _replaceCalendars(const <TaskCalendar>[]);
    _replaceTasks(const <TaskRecord>[]);
    _taskCounts = const <String, int>{};
    _selectedCalendarId = null;
    _defaultCalendarId = null;
    _selectedSmartView = null;
    _viewSelectionGeneration++;
    _searchQuery = '';
    _selectedTag = null;
    _message = null;
    _preferences = _preferences.copyWith(
      clearLastCalendarId: true,
      clearLastSmartView: true,
    );
    await _saveViewPreferences();
    try {
      await _notificationScheduler.cancelAll();
    } on Object {
      // Account removal must not depend on the Android notification service.
    }
    _setState(CloudTasksViewState.signedOut);
  }

  LocalTaskEdit _localEdit(
    TaskRecord record,
    ICalendarDocument document,
    Set<String> changedProperties,
  ) {
    final updatedTask = _codec.decode(
      document,
      calendarId: record.task.calendarId,
    );
    final calendarId = updatedTask.calendarId;
    if (calendarId == null) {
      throw StateError('A cached task must belong to a calendar.');
    }
    final updatedRecord = TaskRecord(
      task: updatedTask,
      href: record.href,
      etag: record.etag,
      rawDocument: document,
      baseDocument: record.baseDocument ?? record.rawDocument,
      isDirty: true,
    );
    return LocalTaskEdit(
      record: updatedRecord,
      operation: PendingTaskOperation.update(
        taskUid: updatedTask.uid,
        calendarId: calendarId,
        changedProperties: changedProperties,
      ),
    );
  }

  Future<bool> _saveEdits(List<LocalTaskEdit> edits) async {
    if (edits.isEmpty ||
        state != CloudTasksViewState.ready ||
        _isSaving ||
        edits.any((edit) => !canEditRecord(edit.record))) {
      return false;
    }
    final pendingEdits = List<LocalTaskEdit>.unmodifiable(edits);
    final localKeys = <String>{
      for (final edit in pendingEdits)
        _taskKey(edit.operation.calendarId, edit.operation.taskUid),
    };
    _locallySavingTaskKeys.addAll(localKeys);
    notifyListeners();
    var savedLocally = false;
    final save = _localEditQueue.then((_) async {
      try {
        _message = null;
        await _taskStore.saveLocalEdits(pendingEdits);
        await _loadCachedData();
        savedLocally = true;
        notifyListeners();
        _schedulePendingWriteback();
        _scheduleNotificationReconcile();
      } on Object catch (error) {
        _message = _safeMessage(error, action: 'Saving the task locally');
      } finally {
        _locallySavingTaskKeys.removeAll(localKeys);
        notifyListeners();
      }
    });
    _localEditQueue = save;
    await save;
    return savedLocally;
  }

  Future<void> _reconcileNotifications() async {
    try {
      final tasks = <CloudTask>[];
      for (final calendar in _calendars) {
        tasks.addAll(
          (await _taskStore.readCalendarTasks(calendar.id))
              .map((record) => record.task),
        );
      }
      await _notificationScheduler.reconcile(tasks);
    } on Object {
      // Notification setup must never prevent CalDAV data from loading or
      // local edits from being persisted. Android can retry on the next sync.
    }
  }

  void _scheduleNotificationReconcile() {
    if (_disposed) {
      return;
    }
    _notificationTimer?.cancel();
    _notificationTimer = Timer(_notificationDelay, () {
      _notificationTimer = null;
      _notificationQueue = _notificationQueue.then(
        (_) => _reconcileNotifications(),
      );
    });
  }

  Future<List<String>> _flushPendingWrites(DavHttpClient dav) async {
    final writer = CalDavTaskWriter(dav);
    final operations = await _taskStore.readPendingOperations();
    final uploadingKeys = <String>{
      for (final operation in operations)
        _taskKey(operation.calendarId, operation.taskUid),
    };
    if (uploadingKeys.isNotEmpty) {
      _uploadingTaskKeys.addAll(uploadingKeys);
    }
    _writebackPreparing = false;
    notifyListeners();
    final warnings = <String>[];
    final blockedBatches = <String>{};
    try {
      for (final operation in operations) {
        final batchId = operation.batchId;
        if (batchId != null && blockedBatches.contains(batchId)) {
          continue;
        }
        final record = await _taskStore.readTask(
          calendarId: operation.calendarId,
          taskUid: operation.taskUid,
        );
        if (record == null) {
          if (batchId != null && operation.batchPhase == 0) {
            blockedBatches.add(batchId);
            warnings.add(
              'A destination copy is missing from the local move batch. '
              'Source tasks were kept; synchronize again after restoring the '
              'local cache.',
            );
            continue;
          }
          await _taskStore.deletePendingOperation(operation.id);
          continue;
        }

        try {
          if (operation.type == PendingOperationType.delete) {
            await writer.delete(record);
            await _taskStore.completePendingDelete(operation);
            continue;
          }
          final serverRecord = operation.type == PendingOperationType.create
              ? await writer.create(record)
              : await writer.put(
                  record,
                  changedProperties: operation.changedProperties,
                );
          await _taskStore.completePendingWrite(serverRecord, operation.id);
        } on TaskWriteConflict catch (conflict) {
          await _taskStore.completePendingWrite(
            conflict.remoteRecord,
            operation.id,
          );
          warnings.add(
            operation.type == PendingOperationType.delete
                ? '${record.task.summary} changed on another device before it '
                    'could be deleted. The server version was kept.'
                : '${record.task.summary} changed in the same field on another '
                    'device. The server version was kept; please apply your '
                    'change again.',
          );
        } on DavHttpException catch (error) {
          if (batchId != null) blockedBatches.add(batchId);
          warnings.add(
            '${record.task.summary} is saved on this device and will retry. '
            '${error.message}',
          );
          break;
        } on CalDavTaskWriteException catch (error) {
          if (batchId != null) blockedBatches.add(batchId);
          warnings.add('${record.task.summary}: ${error.message}');
          if (error.statusCode == 401) {
            break;
          }
        }
      }
    } finally {
      if (_writebackInProgress) {
        _writebackPreparing = true;
      }
      if (uploadingKeys.isNotEmpty) {
        _uploadingTaskKeys.removeAll(uploadingKeys);
      }
      notifyListeners();
    }
    return List<String>.unmodifiable(warnings);
  }

  Future<void> _loadCachedData() async {
    final currentAccount = _account;
    if (currentAccount == null) {
      return;
    }
    _replaceCalendars(await _taskStore.readCalendars(currentAccount.id));
    _taskCounts = await _taskStore.readTaskCounts(currentAccount.id);
    if (_calendars.isEmpty) {
      _selectedCalendarId = null;
      _defaultCalendarId = null;
      _replaceTasks(const <TaskRecord>[]);
      if (_preferences.lastCalendarId != null) {
        _preferences = _preferences.copyWith(clearLastCalendarId: true);
        await _saveViewPreferences();
      }
      return;
    }

    final storedDefault = await _taskStore.readDefaultCalendarId(
      currentAccount.id,
    );
    final validDefault = _calendars.any(
      (calendar) => calendar.id == storedDefault && !calendar.isReadOnly,
    );
    String? fallbackDefault;
    for (final calendar in _calendars) {
      if (!calendar.isReadOnly) {
        fallbackDefault = calendar.id;
        break;
      }
    }
    _defaultCalendarId = validDefault ? storedDefault : fallbackDefault;
    if (_defaultCalendarId != storedDefault) {
      await _taskStore.setDefaultCalendarId(
        currentAccount.id,
        _defaultCalendarId,
      );
    }

    final selectedStillExists = _calendars.any(
      (calendar) => calendar.id == _selectedCalendarId,
    );
    if (!selectedStillExists) {
      _selectedCalendarId = _defaultCalendarId ?? _calendars.first.id;
      _preferences = _preferences.copyWith(
        lastCalendarId: _selectedCalendarId,
      );
      await _saveViewPreferences();
    }
    await _loadTasksForCurrentView();
  }

  Future<void> _loadTasksForCurrentView() async {
    if (isSmartView) {
      final records = <TaskRecord>[];
      for (final calendar in _calendars) {
        records.addAll(await _taskStore.readCalendarTasks(calendar.id));
      }
      _replaceTasks(records);
      return;
    }
    final calendarId = _selectedCalendarId;
    _replaceTasks(
      calendarId == null
          ? const <TaskRecord>[]
          : await _taskStore.readCalendarTasks(calendarId),
    );
  }

  void _replaceCalendars(Iterable<TaskCalendar> calendars) {
    _calendars = List<TaskCalendar>.unmodifiable(calendars);
    _calendarsById = Map<String, TaskCalendar>.unmodifiable(
      <String, TaskCalendar>{
        for (final calendar in _calendars) calendar.id: calendar,
      },
    );
  }

  void _replaceTasks(Iterable<TaskRecord> records) {
    _tasks = List<TaskRecord>.unmodifiable(records);
    _recordsByKey = Map<String, TaskRecord>.unmodifiable(
      <String, TaskRecord>{
        for (final record in _tasks)
          _taskKey(record.task.calendarId, record.task.uid): record,
      },
    );
    final uniqueTags = <String>{};
    final tasksByCalendar = <String?, List<CloudTask>>{};
    for (final record in _tasks) {
      uniqueTags.addAll(record.task.categories);
      tasksByCalendar
          .putIfAbsent(record.task.calendarId, () => <CloudTask>[])
          .add(record.task);
    }
    final tags = uniqueTags.toList()
      ..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
    _availableTags = List<String>.unmodifiable(tags);
    final counts = <String, int>{};
    for (final entry in tasksByCalendar.entries) {
      final recordsByUid = <String, CloudTask>{
        for (final task in entry.value) task.uid: task,
      };
      for (final task in entry.value) {
        counts[_taskKey(entry.key, task.uid)] = 0;
      }
      for (final task in entry.value) {
        var parentUid = task.parentUid;
        final visited = <String>{task.uid};
        while (parentUid != null && visited.add(parentUid)) {
          final parent = recordsByUid[parentUid];
          if (parent == null) {
            break;
          }
          final key = _taskKey(entry.key, parentUid);
          counts[key] = (counts[key] ?? 0) + 1;
          parentUid = parent.parentUid;
        }
      }
    }
    _descendantCounts = Map<String, int>.unmodifiable(counts);
  }

  static String _taskKey(String? calendarId, String uid) =>
      '${calendarId ?? ''}\u0000$uid';

  Future<void> _saveViewPreferences() async {
    try {
      await _taskStore.saveAppPreferences(_preferences);
    } on Object {
      _message = 'The current view changed, but its display preference could '
          'not be saved on this device.';
      notifyListeners();
    }
  }

  List<TaskRecord> get _filteredRecords {
    final query = _searchQuery.trim().toLowerCase();
    final tag = _selectedTag;
    final now = DateTime.now();
    final filtered = _tasks.where((record) {
      final task = record.task;
      if (!_viewFilter.matchesSmartView(
        _selectedSmartView,
        task,
        now: now,
      )) {
        return false;
      }
      if (!_viewFilter.matchesTag(task, tag)) {
        return false;
      }
      return _viewFilter.matchesQuery(task, query);
    }).toList(growable: false);
    if (isSmartView) {
      filtered.sort((left, right) {
        final leftDate = _viewFilter.displayDate(left.task);
        final rightDate = _viewFilter.displayDate(right.task);
        if (leftDate == null && rightDate != null) {
          return 1;
        }
        if (leftDate != null && rightDate == null) {
          return -1;
        }
        final dateComparison =
            leftDate == null ? 0 : leftDate.compareTo(rightDate!);
        return dateComparison != 0
            ? dateComparison
            : left.task.summary.toLowerCase().compareTo(
                  right.task.summary.toLowerCase(),
                );
      });
    }
    return List<TaskRecord>.unmodifiable(filtered);
  }

  List<TaskRecord> _recordsForParent(String? parentUid, {String? calendarId}) {
    final records = _tasks.where(
      (record) =>
          record.task.parentUid == parentUid &&
          (calendarId == null || record.task.calendarId == calendarId),
    );
    final sortedTasks = _ordering.sort(
      records.map((record) => record.task),
      descending: _descending,
    );
    final recordsByUid = <String, TaskRecord>{
      for (final record in records) record.task.uid: record,
    };
    return List<TaskRecord>.unmodifiable(
      sortedTasks.map((task) => recordsByUid[task.uid]!),
    );
  }

  void _setState(CloudTasksViewState nextState) {
    _state = nextState;
    notifyListeners();
  }

  static final Random _secureRandom = Random.secure();

  static String _newUid() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  static Uri _taskHref(Uri calendarHref, String uid) {
    final path = calendarHref.path.endsWith('/')
        ? calendarHref.path
        : '${calendarHref.path}/';
    return calendarHref.replace(
      path: '$path$uid.ics',
      query: null,
      fragment: null,
    );
  }

  static String _safeMessage(Object error, {required String action}) {
    String detail;
    if (error is LoginFlowException ||
        error is CalDavDiscoveryException ||
        error is CalDavTaskReadException ||
        error is CalDavTaskWriteException ||
        error is CalDavCalendarWriteException ||
        error is CalendarSharingException) {
      detail = error.toString();
    } else if (error is DavHttpException) {
      detail = error.message;
    } else if (error is http.ClientException) {
      detail = 'The network connection to Nextcloud was interrupted.';
    } else if (error is PlatformException) {
      final platformMessage = error.message?.toLowerCase() ?? '';
      if (platformMessage.contains('unwrap key') ||
          platformMessage.contains('keystore') ||
          platformMessage.contains('badpadding')) {
        detail = 'Android secure storage could not unlock its encryption key. '
            'Disable app backup, clear Cloud Tasks app storage, and try again.';
      } else {
        detail = 'Android reported platform error ${error.code}.';
      }
    } else if (error is DatabaseException) {
      detail = 'The local database reported an error.';
    } else if (error is FormatException) {
      detail = 'Received data in an unexpected format.';
    } else {
      detail = 'Unexpected ${error.runtimeType} error.';
    }
    return '$action failed. $detail';
  }

  Future<void> close() async {
    _automaticSyncTimer?.cancel();
    _automaticSyncTimer = null;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    _writebackTimer?.cancel();
    _writebackTimer = null;
    await _closeStoreWhenIdle();
  }

  Future<void> _closeStoreWhenIdle() async {
    await _waitForLocalEdits();
    final activeWriteback = _activeWriteback;
    if (activeWriteback != null) {
      await activeWriteback;
    }
    await _notificationQueue;
    await _taskStore.close();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _automaticSyncTimer?.cancel();
    _notificationTimer?.cancel();
    _writebackTimer?.cancel();
    unawaited(_closeStoreWhenIdle());
    super.dispose();
  }
}
