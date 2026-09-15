import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_tasks/src/account/account_store.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_controller.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_preferences.dart';
import 'package:cloud_tasks/src/data/sqlite_task_store.dart';
import 'package:cloud_tasks/src/notifications/task_notification_scheduler.dart';
import 'package:cloud_tasks/src/widgets/cloud_task_list_view.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:url_launcher/url_launcher.dart';

class CloudTasksHomeScreen extends StatefulWidget {
  const CloudTasksHomeScreen({super.key, this.controller});

  final CloudTasksController? controller;

  @override
  State<CloudTasksHomeScreen> createState() => _CloudTasksHomeScreenState();
}

class _CloudTasksHomeScreenState extends State<CloudTasksHomeScreen>
    with WidgetsBindingObserver {
  late final CloudTasksController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        CloudTasksController(
          accountStore: SecureAccountStore(),
          taskStore: SqliteTaskStore(),
          browserLauncher: (url) =>
              launchUrl(url, mode: LaunchMode.externalApplication),
          notificationScheduler: AndroidTaskNotificationScheduler(),
        );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.handleAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final showTaskLists = _showsTaskLists;
        final useDrawer =
            showTaskLists && MediaQuery.sizeOf(context).width < 760;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cloud Tasks'),
            actions: _buildActions(),
          ),
          drawer: useDrawer
              ? Drawer(
                  child: TaskCalendarNavigation(
                    controller: _controller,
                    onSelected: () => Navigator.of(context).pop(),
                  ),
                )
              : null,
          body: SafeArea(child: _buildBody()),
        );
      },
    );
  }

  List<Widget> _buildActions() {
    final hasAccount = _controller.account != null;
    final synchronizing = _controller.isSyncing || _controller.isUploading;
    return <Widget>[
      if (hasAccount && _showsTaskLists)
        IconButton(
          tooltip: _controller.hasActiveFilters
              ? 'Change active task filters'
              : 'Search and filter tasks',
          onPressed: () => unawaited(showTaskFilterSheet(context, _controller)),
          icon: Badge(
            isLabelVisible: _controller.hasActiveFilters,
            child: const Icon(Icons.search),
          ),
        ),
      if (hasAccount &&
          _showsTaskLists &&
          !_controller.isSmartView &&
          _controller.selectedCalendar != null)
        IconButton(
          tooltip: _controller.descending
              ? 'Manual order: higher positions first'
              : 'Manual order: lower positions first',
          onPressed: () => unawaited(_showSortOptions()),
          icon: Badge(
            alignment: AlignmentDirectional.bottomEnd,
            label: Icon(
              _controller.descending
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
              size: 10,
            ),
            child: const Icon(Icons.sort),
          ),
        ),
      if (hasAccount)
        IconButton(
          tooltip: _controller.isUploading
              ? 'Uploading saved changes'
              : 'Synchronize',
          onPressed: synchronizing
              ? null
              : () => unawaited(_controller.refresh()),
          icon: synchronizing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
        ),
      PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'disconnect') {
            unawaited(_confirmDisconnect());
          } else if (value == 'import') {
            unawaited(_importTasks());
          } else if (value == 'export') {
            unawaited(_exportTasks());
          } else if (value == 'delete-completed') {
            unawaited(_confirmDeleteCompleted());
          } else if (value == 'trash') {
            _showTrashInformation();
          } else if (value == 'settings') {
            unawaited(_showSettings());
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          if (_controller.state == CloudTasksViewState.ready &&
              _controller.selectedCalendar != null &&
              !_controller.selectedCalendar!.isReadOnly)
            const PopupMenuItem<String>(
              value: 'import',
              child: Text('Import tasks from .ics'),
            ),
          if (_controller.state == CloudTasksViewState.ready &&
              _controller.selectedCalendar != null)
            const PopupMenuItem<String>(
              value: 'export',
              child: Text('Export list as .ics'),
            ),
          if (_controller.state == CloudTasksViewState.ready &&
              _controller.selectedCalendar != null &&
              !_controller.selectedCalendar!.isReadOnly)
            const PopupMenuItem<String>(
              value: 'delete-completed',
              child: Text('Delete completed tasks'),
            ),
          if (_controller.state == CloudTasksViewState.ready)
            const PopupMenuItem<String>(
              value: 'trash',
              child: Text('Recently deleted'),
            ),
          const PopupMenuItem<String>(
            value: 'settings',
            child: Text('Settings'),
          ),
          if (hasAccount) const PopupMenuDivider(),
          if (hasAccount)
            const PopupMenuItem<String>(
              value: 'disconnect',
              child: Text('Disconnect account'),
            ),
        ],
      ),
    ];
  }

  bool get _showsTaskLists =>
      _controller.state == CloudTasksViewState.ready ||
      (_controller.state == CloudTasksViewState.syncing &&
          _controller.hasCachedData);

  Future<void> _showSortOptions() async {
    final selected = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Manual task order',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose how Nextcloud’s synchronized task positions are '
                    'displayed. This choice is remembered on this device.',
                  ),
                ],
              ),
            ),
            _SortDirectionTile(
              title: 'Lower positions first',
              subtitle: 'Matches the usual Nextcloud “My order” direction',
              icon: Icons.arrow_upward,
              selected: !_controller.descending,
              onTap: () => Navigator.pop(context, false),
            ),
            _SortDirectionTile(
              title: 'Higher positions first',
              subtitle: 'Shows the same synchronized order in reverse',
              icon: Icons.arrow_downward,
              selected: _controller.descending,
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await _controller.setSortDirection(selected);
    }
  }

  Future<void> _showSettings() async {
    var selected = _controller.preferences;
    final saved = await showDialog<CloudTasksPreferences>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<CloudTasksTheme>(
                  initialValue: selected.theme,
                  decoration: const InputDecoration(labelText: 'Appearance'),
                  items: const <DropdownMenuItem<CloudTasksTheme>>[
                    DropdownMenuItem(
                      value: CloudTasksTheme.system,
                      child: Text('Follow system'),
                    ),
                    DropdownMenuItem(
                      value: CloudTasksTheme.light,
                      child: Text('Light'),
                    ),
                    DropdownMenuItem(
                      value: CloudTasksTheme.dark,
                      child: Text('Dark'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(
                        () => selected = selected.copyWith(theme: value),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: selected.automaticSyncMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Automatic sync',
                  ),
                  items: const <DropdownMenuItem<int>>[
                    DropdownMenuItem(value: 0, child: Text('Off')),
                    DropdownMenuItem(
                      value: 15,
                      child: Text('Every 15 minutes'),
                    ),
                    DropdownMenuItem(
                      value: 30,
                      child: Text('Every 30 minutes'),
                    ),
                    DropdownMenuItem(value: 60, child: Text('Every hour')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(
                        () => selected = selected.copyWith(
                          automaticSyncMinutes: value,
                        ),
                      );
                    }
                  },
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Android may defer background work to protect battery. '
                      'Sync also runs at this interval while the app is open.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sync when returning to the app'),
                  subtitle: const Text(
                    'Runs only when the last successful sync is at least one '
                    'minute old.',
                  ),
                  value: selected.syncOnResume,
                  onChanged: (value) => setDialogState(
                    () => selected = selected.copyWith(syncOnResume: value),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    try {
      await _controller.updatePreferences(saved);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save settings: $error')),
        );
      }
    }
  }

  Future<void> _importTasks() async {
    final calendar = _controller.selectedCalendar;
    if (calendar == null || calendar.isReadOnly) {
      return;
    }
    try {
      const typeGroup = XTypeGroup(
        label: 'iCalendar tasks',
        extensions: <String>['ics', 'ical'],
        mimeTypes: <String>['text/calendar'],
      );
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
      if (file == null) {
        return;
      }
      final source = utf8.decode(await file.readAsBytes());
      final count = await _controller.importTasks(
        source,
        calendarId: calendar.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported $count ${count == 1 ? 'task' : 'tasks'}.'),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import tasks: $error')),
        );
      }
    }
  }

  Future<void> _exportTasks() async {
    final calendar = _controller.selectedCalendar;
    if (calendar == null) {
      return;
    }
    try {
      final safeName = calendar.displayName
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final fileName = '${safeName.isEmpty ? 'tasks' : safeName}.ics';
      await share_plus.Share.shareXFiles(<XFile>[
        XFile.fromData(
          Uint8List.fromList(utf8.encode(_controller.exportCalendar(calendar))),
          mimeType: 'text/calendar',
          name: fileName,
        ),
      ], subject: 'Export Nextcloud task list');
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export tasks: $error')),
        );
      }
    }
  }

  Future<void> _confirmDeleteCompleted() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete completed tasks?'),
        content: const Text(
          'Completed tasks in this list will be removed from every synced '
          'device. Nextcloud keeps them temporarily in Calendar’s trash.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete completed'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _controller.deleteCompletedTasks();
    }
  }

  void _showTrashInformation() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recently deleted'),
          content: const Text(
            'Nextcloud keeps deleted tasks in Calendar’s trash, normally for '
            '30 days. Nextcloud does not expose that trash to connected '
            'CalDAV apps, so restore, permanent delete, and empty trash are '
            'available in the Nextcloud Calendar web app.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_controller.state) {
      case CloudTasksViewState.starting:
        return const _ProgressView(message: 'Opening Cloud Tasks…');
      case CloudTasksViewState.authenticating:
        return const _ProgressView(
          message: 'Finish signing in through your browser…',
        );
      case CloudTasksViewState.syncing:
        return _controller.hasCachedData
            ? _buildTaskListsBody()
            : const _ProgressView(message: 'Synchronizing task lists…');
      case CloudTasksViewState.signedOut:
        return _SignInView(onConnect: _controller.connect);
      case CloudTasksViewState.error:
        return _ErrorView(
          message: _controller.message ?? 'Cloud Tasks could not connect.',
          hasAccount: _controller.account != null,
          onRetry: _controller.account == null
              ? null
              : () => unawaited(_controller.refresh()),
          onUseAnotherServer: _controller.disconnect,
        );
      case CloudTasksViewState.ready:
        return _buildTaskListsBody();
    }
  }

  Widget _buildTaskListsBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return CloudTaskListView(controller: _controller);
        }
        return Row(
          children: <Widget>[
            SizedBox(
              width: 296,
              child: TaskCalendarNavigation(controller: _controller),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: CloudTaskListView(controller: _controller)),
          ],
        );
      },
    );
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Disconnect Nextcloud?'),
          content: const Text(
            'This removes the app password and cached tasks from this device. '
            'It does not delete anything from Nextcloud.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disconnect'),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) {
      await _controller.disconnect();
    }
  }
}

class _SignInView extends StatefulWidget {
  const _SignInView({required this.onConnect});

  final Future<void> Function(String serverUrl) onConnect;

  @override
  State<_SignInView> createState() => _SignInViewState();
}

class _SortDirectionTile extends StatelessWidget {
  const _SortDirectionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}

class _SignInViewState extends State<_SignInView> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(
                  Icons.cloud_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Connect to Nextcloud',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cloud Tasks opens your server in the system browser. Your '
                  'normal password is never entered into this app.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  autofillHints: const <String>[AutofillHints.url],
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Nextcloud server',
                    hintText: 'https://cloud.example.com',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    return value == null || value.trim().isEmpty
                        ? 'Enter your Nextcloud server address.'
                        : null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.login),
                  label: const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      unawaited(widget.onConnect(_controller.text));
    }
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.hasAccount,
    required this.onRetry,
    required this.onUseAnotherServer,
  });

  final String message;
  final bool hasAccount;
  final VoidCallback? onRetry;
  final Future<void> Function() onUseAnotherServer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, size: 56),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (onRetry != null)
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            TextButton(
              onPressed: () => unawaited(onUseAnotherServer()),
              child: Text(hasAccount ? 'Disconnect account' : 'Back'),
            ),
          ],
        ),
      ),
    );
  }
}
