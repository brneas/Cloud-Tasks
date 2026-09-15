import 'dart:async';

import 'package:cloud_tasks/src/app/cloud_tasks_controller.dart';
import 'package:cloud_tasks/src/caldav/caldav_calendar_sharing_service.dart';
import 'package:cloud_tasks/src/caldav/caldav_models.dart';
import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/domain/task_view_filter.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_codec.dart';
import 'package:cloud_tasks/src/ordering/task_hierarchy.dart';
import 'package:cloud_tasks/src/sync/sync_contracts.dart';
import 'package:cloud_tasks/src/widgets/recurrence_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class TaskCalendarNavigation extends StatefulWidget {
  const TaskCalendarNavigation({
    required this.controller,
    this.onSelected,
    super.key,
  });

  final CloudTasksController controller;
  final VoidCallback? onSelected;

  @override
  State<TaskCalendarNavigation> createState() => _TaskCalendarNavigationState();
}

class _TaskCalendarNavigationState extends State<TaskCalendarNavigation> {
  late bool _smartViewsExpanded;
  SmartTaskView? _lastSmartView;

  CloudTasksController get controller => widget.controller;
  VoidCallback? get onSelected => widget.onSelected;

  @override
  void initState() {
    super.initState();
    _smartViewsExpanded = controller.isSmartView;
    _lastSmartView = controller.selectedSmartView;
  }

  @override
  void didUpdateWidget(covariant TaskCalendarNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _smartViewsExpanded = controller.isSmartView;
      _lastSmartView = controller.selectedSmartView;
      return;
    }
    final selectedSmartView = controller.selectedSmartView;
    if (selectedSmartView != null && selectedSmartView != _lastSmartView) {
      _smartViewsExpanded = true;
    }
    _lastSmartView = selectedSmartView;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          children: <Widget>[
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.cloud_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              title: const Text('Task lists'),
              subtitle: Text(controller.account?.loginName ?? 'Nextcloud'),
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'MY LISTS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Create task list',
                    onPressed:
                        controller.isSaving ||
                            controller.state != CloudTasksViewState.ready
                        ? null
                        : () => unawaited(_createCalendar(context)),
                    icon: const Icon(Icons.playlist_add),
                  ),
                ],
              ),
            ),
            for (final calendar in controller.calendars)
              _calendarTile(context, calendar),
            if (controller.calendars.isEmpty)
              const ListTile(
                leading: Icon(Icons.playlist_add_outlined),
                title: Text('No task lists yet'),
                subtitle: Text('Use the add button above to create one.'),
              ),
            const Divider(height: 24),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.auto_awesome_mosaic_outlined),
              title: const Text('Smart Views'),
              subtitle: Text(
                controller.isSmartView
                    ? controller.viewTitle
                    : 'Important, Today, Week, and more',
              ),
              trailing: Icon(
                _smartViewsExpanded ? Icons.expand_less : Icons.expand_more,
              ),
              onTap: () =>
                  setState(() => _smartViewsExpanded = !_smartViewsExpanded),
            ),
            if (_smartViewsExpanded) ...<Widget>[
              _smartTile(
                context,
                SmartTaskView.important,
                Icons.star_outline,
                'Important',
              ),
              _smartTile(
                context,
                SmartTaskView.current,
                Icons.play_circle_outline,
                'Current',
              ),
              _smartTile(
                context,
                SmartTaskView.today,
                Icons.today_outlined,
                'Today',
              ),
              _smartTile(
                context,
                SmartTaskView.nextSevenDays,
                Icons.date_range_outlined,
                'Week',
              ),
              _smartTile(
                context,
                SmartTaskView.upcoming,
                Icons.upcoming_outlined,
                'Upcoming',
              ),
              _smartTile(
                context,
                SmartTaskView.overdue,
                Icons.warning_amber_outlined,
                'Overdue',
              ),
              _smartTile(
                context,
                SmartTaskView.completed,
                Icons.task_alt,
                'Completed',
              ),
              _smartTile(
                context,
                SmartTaskView.all,
                Icons.all_inclusive,
                'All tasks',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _smartTile(
    BuildContext context,
    SmartTaskView view,
    IconData icon,
    String label,
  ) {
    return ListTile(
      selected: controller.selectedSmartView == view,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        onSelected?.call();
        unawaited(controller.selectSmartView(view));
      },
    );
  }

  Widget _calendarTile(BuildContext context, TaskCalendar calendar) {
    final selected =
        !controller.isSmartView && calendar.id == controller.selectedCalendarId;
    final color =
        _calendarColor(calendar.color) ?? Theme.of(context).colorScheme.primary;
    return ListTile(
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(
        calendar.isReadOnly ? Icons.lock_outline : Icons.checklist,
        color: color,
      ),
      title: Row(
        children: <Widget>[
          Expanded(child: Text(calendar.displayName)),
          if (calendar.id == controller.defaultCalendarId)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Tooltip(
                message: 'Default list',
                child: Icon(Icons.star, size: 16),
              ),
            ),
        ],
      ),
      subtitle: calendar.isSharedWithMe
          ? Text(
              calendar.isReadOnly ? 'Shared • Read only' : 'Shared • Can edit',
            )
          : calendar.isReadOnly
          ? const Text('Read only')
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _CountBadge(count: controller.taskCount(calendar.id)),
          if (!calendar.isReadOnly || calendar.isSharedWithMe)
            PopupMenuButton<String>(
              tooltip: 'List actions',
              onSelected: (value) =>
                  unawaited(_handleCalendarAction(context, calendar, value)),
              itemBuilder: (context) {
                final index = controller.calendars.indexOf(calendar);
                final canManage = controller.canManageCalendar(calendar);
                final canReorder = !controller.calendars.any(
                  (item) => item.isReadOnly || item.isSharedWithMe,
                );
                return <PopupMenuEntry<String>>[
                  if (!calendar.isReadOnly &&
                      calendar.id != controller.defaultCalendarId)
                    const PopupMenuItem(
                      value: 'default',
                      child: Text('Set as default'),
                    ),
                  if (canManage)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit list'),
                    ),
                  if (controller.canShareCalendar(calendar))
                    const PopupMenuItem(
                      value: 'sharing',
                      child: Text('Manage sharing'),
                    ),
                  if (canManage && canReorder && index > 0)
                    const PopupMenuItem(
                      value: 'up',
                      child: Text('Move list up'),
                    ),
                  if (canManage &&
                      canReorder &&
                      index < controller.calendars.length - 1)
                    const PopupMenuItem(
                      value: 'down',
                      child: Text('Move list down'),
                    ),
                  if (canManage || calendar.isSharedWithMe)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        calendar.isSharedWithMe
                            ? 'Remove shared list'
                            : 'Delete list',
                      ),
                    ),
                ];
              },
            ),
        ],
      ),
      onTap: () {
        onSelected?.call();
        unawaited(controller.selectCalendar(calendar.id));
      },
    );
  }

  Future<void> _handleCalendarAction(
    BuildContext context,
    TaskCalendar calendar,
    String action,
  ) async {
    final index = controller.calendars.indexOf(calendar);
    if (action == 'up') {
      await controller.reorderCalendars(index, index - 1);
      return;
    }
    if (action == 'down') {
      await controller.reorderCalendars(index, index + 2);
      return;
    }
    if (action == 'edit') {
      final draft = await _showCalendarEditor(context, calendar: calendar);
      if (draft != null) {
        await controller.updateCalendar(
          calendar,
          displayName: draft.name,
          color: draft.color,
        );
      }
      return;
    }
    if (action == 'default') {
      await controller.setDefaultCalendar(calendar);
      return;
    }
    if (action == 'sharing') {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) =>
            _CalendarSharingSheet(controller: controller, calendar: calendar),
      );
      return;
    }
    if (action == 'delete') {
      final shared = calendar.isSharedWithMe;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            shared
                ? 'Remove “${calendar.displayName}” from this account?'
                : 'Delete “${calendar.displayName}”?',
          ),
          content: Text(
            shared
                ? 'This stops sharing the list with you. It does not delete '
                      'the owner’s list or tasks.'
                : 'This permanently deletes the list and its '
                      '${controller.taskCount(calendar.id)} tasks from '
                      'Nextcloud and every connected device.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(shared ? 'Remove list' : 'Delete list'),
            ),
          ],
        ),
      );
      if (confirmed ?? false) {
        await controller.deleteCalendar(calendar);
      }
    }
  }

  Future<void> _createCalendar(BuildContext context) async {
    final draft = await _showCalendarEditor(context);
    if (draft != null) {
      await controller.createCalendar(
        displayName: draft.name,
        color: draft.color,
      );
    }
  }

  Future<_CalendarDraft?> _showCalendarEditor(
    BuildContext context, {
    TaskCalendar? calendar,
  }) {
    return showDialog<_CalendarDraft>(
      context: context,
      builder: (context) => CalendarEditorDialog(calendar: calendar),
    );
  }
}

class CalendarEditorDialog extends StatefulWidget {
  const CalendarEditorDialog({this.calendar, super.key});

  final TaskCalendar? calendar;

  @override
  State<CalendarEditorDialog> createState() => _CalendarEditorDialogState();
}

class _CalendarEditorDialogState extends State<CalendarEditorDialog> {
  static const _colors = <String>[
    '#0082C9',
    '#46BA61',
    '#F4A331',
    '#E9322D',
    '#9B59B6',
    '#795548',
    '#607D8B',
    '#E91E63',
  ];

  late final TextEditingController _nameController;
  late String _selectedColor;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.calendar?.displayName ?? '',
    );
    final savedColor = widget.calendar?.color?.trim();
    final candidate = savedColor != null && savedColor.length >= 7
        ? savedColor.substring(0, 7).toUpperCase()
        : _colors.first;
    _selectedColor = _colors.contains(candidate) ? candidate : _colors.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.calendar == null ? 'Create task list' : 'Edit task list',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'List name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Color', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final color in _colors)
                ChoiceChip(
                  label: const SizedBox.square(dimension: 18),
                  avatar: CircleAvatar(backgroundColor: _calendarColor(color)),
                  selected: _selectedColor == color,
                  onSelected: (_) => setState(() => _selectedColor = color),
                ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isNotEmpty) {
              Navigator.pop(
                context,
                _CalendarDraft(name: name, color: _selectedColor),
              );
            }
          },
          child: Text(widget.calendar == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

class _CalendarDraft {
  const _CalendarDraft({required this.name, required this.color});

  final String name;
  final String color;
}

class _CalendarSharingSheet extends StatefulWidget {
  const _CalendarSharingSheet({
    required this.controller,
    required this.calendar,
  });

  final CloudTasksController controller;
  final TaskCalendar calendar;

  @override
  State<_CalendarSharingSheet> createState() => _CalendarSharingSheetState();
}

class _CalendarSharingSheetState extends State<_CalendarSharingSheet> {
  List<CalendarShare> _shares = const <CalendarShare>[];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        top: 12,
        right: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Share “${widget.calendar.displayName}”',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Share with a user or group',
                  onPressed: _loading ? null : () => unawaited(_addShare()),
                  icon: const Icon(Icons.person_add_alt_1),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Share with a Nextcloud username or group ID. Read-only is the '
              'safer default; enable editing only when needed.',
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(_error!)),
                      TextButton(
                        onPressed: () => unawaited(_reload()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: !_loading && _shares.isEmpty && _error == null
                  ? const Center(
                      child: Text('This list is not shared with anyone.'),
                    )
                  : ListView.builder(
                      itemCount: _shares.length,
                      itemBuilder: (context, index) {
                        final share = _shares[index];
                        return ListTile(
                          leading: Icon(
                            share.kind == CalendarShareKind.group
                                ? Icons.group_outlined
                                : Icons.person_outline,
                          ),
                          title: Text(share.displayName),
                          subtitle: Text(
                            share.kind == CalendarShareKind.group
                                ? 'Group'
                                : 'User',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Text('Can edit'),
                              Switch(
                                value: share.canWrite,
                                onChanged: _loading
                                    ? null
                                    : (value) => unawaited(
                                        _setPermission(share, value),
                                      ),
                              ),
                              IconButton(
                                tooltip: 'Remove share',
                                onPressed: _loading
                                    ? null
                                    : () => unawaited(_removeShare(share)),
                                icon: const Icon(Icons.person_remove_outlined),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            FilledButton.icon(
              onPressed: _loading ? null : () => unawaited(_addShare()),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Share with user or group'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shares = await widget.controller.loadCalendarShares(
        widget.calendar,
      );
      if (!mounted) {
        return;
      }
      setState(() => _shares = shares);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _addShare() async {
    final draft = await _showShareEditor(context);
    if (draft == null || !mounted) {
      return;
    }
    await _runChange(
      () => widget.controller.shareCalendar(
        calendar: widget.calendar,
        recipientId: draft.recipientId,
        kind: draft.kind,
        canWrite: draft.canWrite,
      ),
    );
  }

  Future<void> _setPermission(CalendarShare share, bool canWrite) async {
    await _runChange(
      () => widget.controller.updateCalendarSharePermission(
        calendar: widget.calendar,
        share: share,
        canWrite: canWrite,
      ),
    );
  }

  Future<void> _removeShare(CalendarShare share) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stop sharing with ${share.displayName}?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove share'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) {
      return;
    }
    await _runChange(
      () => widget.controller.removeCalendarShare(
        calendar: widget.calendar,
        share: share,
      ),
    );
  }

  Future<void> _runChange(Future<bool> Function() change) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final saved = await change();
    if (!mounted) {
      return;
    }
    if (saved) {
      await _reload();
      return;
    }
    setState(() {
      _loading = false;
      _error = widget.controller.message ?? 'The sharing change failed.';
    });
  }

  Future<_ShareDraft?> _showShareEditor(BuildContext context) {
    return showDialog<_ShareDraft>(
      context: context,
      builder: (context) => const ShareEditorDialog(),
    );
  }
}

class ShareEditorDialog extends StatefulWidget {
  const ShareEditorDialog({super.key});

  @override
  State<ShareEditorDialog> createState() => _ShareEditorDialogState();
}

class _ShareEditorDialogState extends State<ShareEditorDialog> {
  final _textController = TextEditingController();
  CalendarShareKind _kind = CalendarShareKind.user;
  bool _canWrite = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share task list'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<CalendarShareKind>(
            initialValue: _kind,
            decoration: const InputDecoration(
              labelText: 'Recipient type',
              border: OutlineInputBorder(),
            ),
            items: const <DropdownMenuItem<CalendarShareKind>>[
              DropdownMenuItem(
                value: CalendarShareKind.user,
                child: Text('User'),
              ),
              DropdownMenuItem(
                value: CalendarShareKind.group,
                child: Text('Group'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _kind = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            autofocus: true,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: _kind == CalendarShareKind.group
                  ? 'Nextcloud group ID'
                  : 'Nextcloud username',
              border: const OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Can edit tasks'),
            value: _canWrite,
            onChanged: (value) => setState(() => _canWrite = value),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final recipientId = _textController.text.trim();
            if (recipientId.isNotEmpty) {
              Navigator.pop(
                context,
                _ShareDraft(
                  recipientId: recipientId,
                  kind: _kind,
                  canWrite: _canWrite,
                ),
              );
            }
          },
          child: const Text('Share'),
        ),
      ],
    );
  }
}

class _ShareDraft {
  const _ShareDraft({
    required this.recipientId,
    required this.kind,
    required this.canWrite,
  });

  final String recipientId;
  final CalendarShareKind kind;
  final bool canWrite;
}

Future<void> showTaskFilterSheet(
  BuildContext context,
  CloudTasksController controller,
) async {
  final draft = await showModalBottomSheet<_TaskFilterDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _TaskFilterSheet(controller: controller),
  );
  if (draft != null) {
    controller.setFilters(query: draft.query, tag: draft.tag);
  }
}

class _TaskFilterSheet extends StatefulWidget {
  const _TaskFilterSheet({required this.controller});

  final CloudTasksController controller;

  @override
  State<_TaskFilterSheet> createState() => _TaskFilterSheetState();
}

class _TaskFilterSheetState extends State<_TaskFilterSheet> {
  late final TextEditingController _searchController;
  String? _selectedTag;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.controller.searchQuery,
    );
    _selectedTag = widget.controller.selectedTag;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Find tasks',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'Search',
              hintText: 'Titles, notes, tags, or locations',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _apply(),
          ),
          if (widget.controller.availableTags.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text('Tag', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('All tags'),
                  selected: _selectedTag == null,
                  onSelected: (_) => setState(() => _selectedTag = null),
                ),
                for (final tag in widget.controller.availableTags)
                  ChoiceChip(
                    label: Text(tag),
                    selected: _selectedTag == tag,
                    onSelected: (_) => setState(
                      () => _selectedTag = _selectedTag == tag ? null : tag,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const _TaskFilterDraft(query: '')),
                child: const Text('Clear'),
              ),
              const Spacer(),
              FilledButton(onPressed: _apply, child: const Text('Apply')),
            ],
          ),
        ],
      ),
    );
  }

  void _apply() {
    Navigator.pop(
      context,
      _TaskFilterDraft(query: _searchController.text, tag: _selectedTag),
    );
  }
}

class _TaskFilterDraft {
  const _TaskFilterDraft({required this.query, this.tag});

  final String query;
  final String? tag;
}

class CloudTaskListView extends StatelessWidget {
  const CloudTaskListView({required this.controller, super.key});

  final CloudTasksController controller;

  @override
  Widget build(BuildContext context) {
    final calendar = controller.selectedCalendar;
    if (calendar == null && !controller.isSmartView) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Create or choose a task list from the navigation panel.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final taskTree = controller.taskTree;
    final taskCount = _taskNodeCount(taskTree);
    final creationCalendar = controller.taskCreationCalendar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (controller.message != null)
          MaterialBanner(
            content: Text(controller.message!),
            actions: <Widget>[
              TextButton(
                onPressed: controller.clearMessage,
                child: const Text('Dismiss'),
              ),
              TextButton(
                onPressed: () => unawaited(controller.refresh()),
                child: const Text('Synchronize'),
              ),
            ],
          ),
        if (controller.isSyncing || controller.isUploading)
          const LinearProgressIndicator(minHeight: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      controller.viewTitle,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}'
                      ' • ${controller.viewSubtitle}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (calendar?.isReadOnly ?? false) const Icon(Icons.lock_outline),
            ],
          ),
        ),
        if (controller.hasActiveFilters)
          _ActiveTaskFilters(controller: controller),
        if (controller.isSaving) const LinearProgressIndicator(),
        Expanded(
          child: taskTree.isEmpty
              ? RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: _EmptyTaskView(controller: controller),
                )
              : RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: _TaskGroup(
                    controller: controller,
                    nodes: taskTree,
                    parentUid: null,
                    depth: 0,
                  ),
                ),
        ),
        if (creationCalendar != null)
          Material(
            elevation: 3,
            shadowColor: Colors.transparent,
            color: Theme.of(context).colorScheme.surface,
            child: _TaskComposer(
              key: ValueKey<String>('task-composer-${creationCalendar.id}'),
              controller: controller,
              calendarId: creationCalendar.id,
              calendarName: creationCalendar.displayName,
            ),
          ),
      ],
    );
  }
}

class _EmptyTaskView extends StatelessWidget {
  const _EmptyTaskView({required this.controller});

  final CloudTasksController controller;

  @override
  Widget build(BuildContext context) {
    final filtered = controller.hasActiveFilters;
    final completed = controller.selectedSmartView == SmartTaskView.completed;
    final title = filtered
        ? 'No matching tasks'
        : completed
        ? 'No completed tasks'
        : controller.isSmartView
        ? 'Nothing here right now'
        : 'This list is empty';
    final description = filtered
        ? 'Try changing or clearing the active search and tag filters.'
        : controller.isSmartView
        ? 'Tasks will appear here automatically when they match this view.'
        : 'Add your first task below. It will be available offline and '
              'synchronized with Nextcloud.';
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      filtered ? Icons.search_off : Icons.task_alt,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (filtered) ...<Widget>[
                      const SizedBox(height: 20),
                      FilledButton.tonalIcon(
                        onPressed: controller.clearFilters,
                        icon: const Icon(Icons.filter_alt_off),
                        label: const Text('Clear filters'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveTaskFilters extends StatelessWidget {
  const _ActiveTaskFilters({required this.controller});

  final CloudTasksController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Row(
        children: <Widget>[
          if (controller.searchQuery.trim().isNotEmpty)
            InputChip(
              avatar: const Icon(Icons.search, size: 18),
              label: Text('“${controller.searchQuery.trim()}”'),
              onDeleted: () =>
                  controller.setFilters(query: '', tag: controller.selectedTag),
            ),
          if (controller.searchQuery.trim().isNotEmpty &&
              controller.selectedTag != null)
            const SizedBox(width: 6),
          if (controller.selectedTag != null)
            InputChip(
              avatar: const Icon(Icons.label_outline, size: 18),
              label: Text(controller.selectedTag!),
              onDeleted: () =>
                  controller.setFilters(query: controller.searchQuery),
            ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: controller.clearFilters,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _TaskComposer extends StatefulWidget {
  const _TaskComposer({
    required this.controller,
    required this.calendarId,
    required this.calendarName,
    this.parentUid,
    this.compact = false,
    super.key,
  });

  final CloudTasksController controller;
  final String calendarId;
  final String calendarName;
  final String? parentUid;
  final bool compact;

  @override
  State<_TaskComposer> createState() => _TaskComposerState();
}

class _TaskComposerState extends State<_TaskComposer> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _submitting = false;

  @override
  void didUpdateWidget(covariant _TaskComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.calendarName != widget.calendarName) {
      _textController.clear();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        widget.controller.canCreateTaskIn(widget.calendarId) && !_submitting;
    return Padding(
      padding: widget.compact
          ? const EdgeInsets.only(top: 8)
          : const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: TextField(
        controller: _textController,
        focusNode: _focusNode,
        enabled: enabled,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => unawaited(_submit()),
        decoration: InputDecoration(
          hintText: widget.parentUid == null
              ? 'Add a task to ${widget.calendarName}…'
              : 'Add a subtask…',
          prefixIcon: Icon(
            widget.parentUid == null
                ? Icons.add_task
                : Icons.subdirectory_arrow_right,
          ),
          suffixIcon: _submitting
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Add task',
                      onPressed: enabled ? () => unawaited(_submit()) : null,
                      icon: const Icon(Icons.add),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More add options',
                      enabled: enabled,
                      icon: const Icon(Icons.more_vert),
                      onSelected: (_) => unawaited(_addMultiple()),
                      itemBuilder: (context) => const <PopupMenuEntry<String>>[
                        PopupMenuItem(
                          value: 'many',
                          child: Text('Add multiple tasks'),
                        ),
                      ],
                    ),
                  ],
                ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final summary = _textController.text.trim();
    if (summary.isEmpty || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    var submitted = false;
    try {
      await widget.controller.createTask(
        summary,
        parentUid: widget.parentUid,
        calendarId: widget.calendarId,
      );
      submitted = true;
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
    if (!mounted || !submitted) return;
    _textController.clear();
    _focusNode.requestFocus();
  }

  Future<void> _addMultiple() async {
    final summaries = await showDialog<List<String>>(
      context: context,
      builder: (context) => const _BulkTaskDialog(),
    );
    if (summaries == null || summaries.isEmpty || !mounted) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.controller.createTasks(
        summaries,
        parentUid: widget.parentUid,
        calendarId: widget.calendarId,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _BulkTaskDialog extends StatefulWidget {
  const _BulkTaskDialog();

  @override
  State<_BulkTaskDialog> createState() => _BulkTaskDialogState();
}

class _BulkTaskDialogState extends State<_BulkTaskDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add multiple tasks'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 6,
        maxLines: 12,
        decoration: const InputDecoration(
          hintText: 'One task per line',
          border: OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final tasks = _controller.text
                .split(RegExp(r'\r?\n'))
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty)
                .toList(growable: false);
            if (tasks.isNotEmpty) {
              Navigator.pop(context, tasks);
            }
          },
          child: const Text('Add tasks'),
        ),
      ],
    );
  }
}

class _TaskGroup extends StatelessWidget {
  const _TaskGroup({
    required this.controller,
    required this.nodes,
    required this.parentUid,
    required this.depth,
  });

  final CloudTasksController controller;
  final List<TaskHierarchyNode> nodes;
  final String? parentUid;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final separatesCompleted =
        controller.selectedSmartView != SmartTaskView.completed;
    final completedNodes = separatesCompleted
        ? nodes.where((node) => node.task.isClosed).toList(growable: false)
        : const <TaskHierarchyNode>[];
    final activeNodes = completedNodes.isEmpty
        ? nodes
        : nodes.where((node) => !node.task.isClosed).toList(growable: false);
    final displayedUids = activeNodes.map((node) => node.task.uid).toList();
    final viewKey =
        controller.selectedCalendarId ??
        controller.selectedSmartView?.name ??
        'all';
    return ReorderableListView.builder(
      padding: depth == 0
          ? const EdgeInsets.fromLTRB(8, 4, 8, 24)
          : const EdgeInsets.only(left: 18),
      physics: depth == 0
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      primary: depth == 0,
      shrinkWrap: depth > 0,
      buildDefaultDragHandles: false,
      itemCount: activeNodes.length,
      footer: completedNodes.isEmpty
          ? null
          : _CompletedTaskSection(
              key: ValueKey<String>(
                'completed-$viewKey-${parentUid ?? 'root'}-$depth',
              ),
              controller: controller,
              nodes: completedNodes,
              depth: depth,
            ),
      onReorderItem: (oldIndex, newIndex) => unawaited(
        controller.reorderTaskGroup(
          parentUid: parentUid,
          displayedUids: displayedUids,
          oldIndex: oldIndex,
          // The ordering service retains Flutter's original callback contract.
          newIndex: newIndex > oldIndex ? newIndex + 1 : newIndex,
        ),
      ),
      itemBuilder: (context, index) {
        final node = activeNodes[index];
        return _TaskBranch(
          key: ValueKey<String>(
            'branch-${node.task.calendarId}-${node.task.uid}',
          ),
          controller: controller,
          node: node,
          index: index,
          depth: depth,
          allowReorder: true,
        );
      },
    );
  }
}

class _CompletedTaskSection extends StatefulWidget {
  const _CompletedTaskSection({
    required this.controller,
    required this.nodes,
    required this.depth,
    super.key,
  });

  final CloudTasksController controller;
  final List<TaskHierarchyNode> nodes;
  final int depth;

  @override
  State<_CompletedTaskSection> createState() => _CompletedTaskSectionState();
}

class _CompletedTaskSectionState extends State<_CompletedTaskSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = _closedTaskNodeCount(widget.nodes);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Card.outlined(
            margin: const EdgeInsets.symmetric(vertical: 4),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Completed'),
              subtitle: Text('$count ${count == 1 ? 'task' : 'tasks'}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.depth == 0 &&
                      widget.controller.selectedCalendar?.isReadOnly == false)
                    TextButton.icon(
                      onPressed: widget.controller.canRestoreCompletedTasks
                          ? () => unawaited(_restoreAll(context))
                          : null,
                      icon: const Icon(Icons.settings_backup_restore, size: 18),
                      label: const Text('Restore all'),
                    ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
              onTap: () => setState(() => _expanded = !_expanded),
            ),
          ),
          if (_expanded)
            for (var index = 0; index < widget.nodes.length; index++)
              _TaskBranch(
                key: ValueKey<String>(
                  'completed-${widget.nodes[index].task.calendarId}-'
                  '${widget.nodes[index].task.uid}',
                ),
                controller: widget.controller,
                node: widget.nodes[index],
                index: index,
                depth: widget.depth,
                allowReorder: false,
              ),
        ],
      ),
    );
  }

  Future<void> _restoreAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final restored = await widget.controller.restoreCompletedTasks();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            restored == 0
                ? 'No completed tasks could be restored.'
                : '$restored completed '
                      '${restored == 1 ? 'task was' : 'tasks were'} restored.',
          ),
        ),
      );
  }
}

class _TaskBranch extends StatelessWidget {
  const _TaskBranch({
    required this.controller,
    required this.node,
    required this.index,
    required this.depth,
    required this.allowReorder,
    super.key,
  });

  final CloudTasksController controller;
  final TaskHierarchyNode node;
  final int index;
  final int depth;
  final bool allowReorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey<String>('${node.task.calendarId}-${node.task.uid}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TaskCard(
          key: ValueKey<String>(
            'card-${node.task.calendarId}-${node.task.uid}',
          ),
          controller: controller,
          record: controller.recordForTask(node.task),
          index: index,
          allowReorder: allowReorder,
        ),
        if (node.children.isNotEmpty)
          _TaskGroup(
            controller: controller,
            nodes: node.children,
            parentUid: node.task.uid,
            depth: depth + 1,
          ),
      ],
    );
  }
}

class _TaskCard extends StatefulWidget {
  const _TaskCard({
    required this.controller,
    required this.record,
    required this.index,
    required this.allowReorder,
    super.key,
  });

  final CloudTasksController controller;
  final TaskRecord record;
  final int index;
  final bool allowReorder;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final FocusNode _titleFocus;
  late final FocusNode _descriptionFocus;
  bool _expanded = false;
  bool _editingDescription = false;
  late double _progressDraft;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.record.task.summary);
    _descriptionController = TextEditingController(
      text: widget.record.task.description ?? '',
    );
    _titleFocus = FocusNode()..addListener(_onTitleFocusChanged);
    _descriptionFocus = FocusNode()..addListener(_onDescriptionFocusChanged);
    _progressDraft = _taskProgress(widget.record.task).toDouble();
  }

  @override
  void didUpdateWidget(covariant _TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_titleFocus.hasFocus &&
        _titleController.text != widget.record.task.summary) {
      _titleController.text = widget.record.task.summary;
    }
    final description = widget.record.task.description ?? '';
    if (!_descriptionFocus.hasFocus &&
        _descriptionController.text != description) {
      _descriptionController.text = description;
    }
    if (oldWidget.record.task.percentComplete !=
            widget.record.task.percentComplete ||
        oldWidget.record.task.status != widget.record.task.status) {
      _progressDraft = _taskProgress(widget.record.task).toDouble();
    }
  }

  @override
  void dispose() {
    _titleFocus.removeListener(_onTitleFocusChanged);
    _descriptionFocus.removeListener(_onDescriptionFocusChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.record.task;
    final completed = task.isCompleted;
    final canEdit = widget.controller.canEditRecord(widget.record);
    final writable =
        !(widget.controller.calendarForRecord(widget.record)?.isReadOnly ??
            true);
    final metadata = _metadataChips(context);
    return Card.outlined(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Row(
              children: <Widget>[
                Semantics(
                  label: completed
                      ? 'Mark ${task.summary} incomplete'
                      : 'Mark ${task.summary} complete',
                  child: Checkbox(
                    value: completed,
                    onChanged: canEdit
                        ? (_) => unawaited(
                            widget.controller.toggleCompletion(widget.record),
                          )
                        : null,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    focusNode: _titleFocus,
                    enabled: writable,
                    readOnly: !canEdit,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _titleFocus.unfocus(),
                    onTapOutside: (_) => _titleFocus.unfocus(),
                    style: completed
                        ? const TextStyle(
                            decoration: TextDecoration.lineThrough,
                          )
                        : null,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      filled: false,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _expanded ? 'Hide details' : 'Show details',
                  onPressed: () {
                    if (_expanded) {
                      _descriptionFocus.unfocus();
                    }
                    setState(() => _expanded = !_expanded);
                  },
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ),
                if (widget.allowReorder &&
                    widget.controller.canReorderSelectedView)
                  Semantics(
                    label: 'Reorder ${task.summary}',
                    button: true,
                    child: ReorderableDragStartListener(
                      index: widget.index,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  )
                else if (!writable)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Tooltip(
                      message: 'Read-only task',
                      child: Icon(Icons.lock_outline),
                    ),
                  ),
              ],
            ),
          ),
          if (metadata.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 6, runSpacing: 4, children: metadata),
              ),
            ),
          if (_expanded) _buildDetails(context, canEdit, writable),
        ],
      ),
    );
  }

  List<Widget> _metadataChips(BuildContext context) {
    final task = widget.record.task;
    final chips = <Widget>[];
    if (task.start != null) {
      chips.add(
        _SmallChip(
          icon: Icons.play_circle_outline,
          label: 'Starts ${_dateLabel(task.start!)}',
        ),
      );
    }
    if (task.due != null) {
      chips.add(
        _SmallChip(
          icon: Icons.event_outlined,
          label: 'Due ${_dateLabel(task.due!)}',
        ),
      );
    }
    if (widget.controller.isSmartView) {
      final calendar = widget.controller.calendarForRecord(widget.record);
      if (calendar != null) {
        chips.add(
          _SmallChip(
            icon: Icons.list_alt,
            label: calendar.displayName,
            color: _calendarColor(calendar.color)?.withValues(alpha: 0.18),
          ),
        );
      }
    }
    if (task.priority != null && task.priority != 0) {
      chips.add(
        _SmallChip(
          icon: Icons.flag_outlined,
          label: _priorityLabel(task.priority),
        ),
      );
    }
    if (task.pinned) {
      chips.add(
        const _SmallChip(icon: Icons.push_pin_outlined, label: 'Pinned'),
      );
    }
    if (task.privacy != null) {
      chips.add(
        _SmallChip(
          icon: Icons.shield_outlined,
          label: switch (task.privacy!) {
            CloudTaskPrivacy.public => 'Public',
            CloudTaskPrivacy.private => 'Private',
            CloudTaskPrivacy.confidential => 'Confidential',
          },
        ),
      );
    }
    if ((task.description ?? '').isNotEmpty) {
      chips.add(const _SmallChip(icon: Icons.notes, label: 'Notes'));
    }
    final descendants = widget.controller.descendantCount(widget.record);
    if (descendants > 0) {
      chips.add(
        _SmallChip(
          icon: Icons.account_tree_outlined,
          label: '$descendants ${descendants == 1 ? 'subtask' : 'subtasks'}',
        ),
      );
    }
    if (task.categories.isNotEmpty) {
      chips.add(
        _SmallChip(
          icon: Icons.sell_outlined,
          label: task.categories.join(', '),
        ),
      );
    }
    if (task.location != null) {
      chips.add(
        const _SmallChip(icon: Icons.place_outlined, label: 'Location'),
      );
    }
    if (task.url != null) {
      chips.add(const _SmallChip(icon: Icons.link, label: 'Link'));
    }
    if (task.recurrenceRule != null) {
      chips.add(
        _SmallChip(
          icon: Icons.repeat,
          label: _recurrenceLabel(task.recurrenceRule),
        ),
      );
    }
    if (task.reminders.isNotEmpty) {
      chips.add(
        _SmallChip(
          icon: Icons.notifications_outlined,
          label: task.reminders.length == 1
              ? _reminderLabel(context, task.reminders.first)
              : '${task.reminders.length} reminders',
        ),
      );
    }
    if (widget.record.isDirty) {
      chips.add(
        _SmallChip(
          icon: Icons.cloud_upload_outlined,
          label: 'Waiting to sync',
          color: Theme.of(context).colorScheme.tertiaryContainer,
        ),
      );
    }
    return chips;
  }

  Widget _buildDetails(BuildContext context, bool canEdit, bool writable) {
    final task = widget.record.task;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_editingDescription || (task.description ?? '').isEmpty)
            TextField(
              controller: _descriptionController,
              focusNode: _descriptionFocus,
              enabled: writable,
              readOnly: !canEdit,
              minLines: 2,
              maxLines: 8,
              onTapOutside: (_) => _descriptionFocus.unfocus(),
              decoration: InputDecoration(
                labelText: 'Notes (Markdown)',
                hintText: 'Add details…',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
                suffixIcon: _editingDescription
                    ? IconButton(
                        tooltip: 'Preview notes',
                        onPressed: () {
                          _descriptionFocus.unfocus();
                          setState(() => _editingDescription = false);
                        },
                        icon: const Icon(Icons.visibility_outlined),
                      )
                    : null,
              ),
            )
          else
            Card.outlined(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          'Notes',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const Spacer(),
                        if (canEdit)
                          IconButton(
                            tooltip: 'Edit Markdown notes',
                            onPressed: () {
                              setState(() => _editingDescription = true);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  _descriptionFocus.requestFocus();
                                }
                              });
                            },
                            icon: const Icon(Icons.edit_outlined),
                          ),
                      ],
                    ),
                    MarkdownBody(
                      data: task.description!,
                      selectable: true,
                      imageBuilder: (uri, title, alt) => const Tooltip(
                        message: 'Remote images are not loaded for privacy',
                        child: Icon(Icons.hide_image_outlined),
                      ),
                      onTapLink: (_text, href, _title) {
                        final uri = href == null ? null : Uri.tryParse(href);
                        if (uri != null &&
                            (uri.scheme == 'https' || uri.scheme == 'http')) {
                          unawaited(
                            launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (writable && !widget.controller.isSmartView)
            _TaskComposer(
              controller: widget.controller,
              calendarId: task.calendarId!,
              calendarName: '',
              parentUid: task.uid,
              compact: true,
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: canEdit
                    ? () => unawaited(_chooseParent(context))
                    : null,
                icon: const Icon(Icons.account_tree_outlined),
                label: Text(
                  task.parentUid == null ? 'Make subtask' : 'Change parent',
                ),
              ),
              if (task.parentUid != null)
                TextButton.icon(
                  onPressed: canEdit
                      ? () => unawaited(
                          widget.controller.reparentTask(widget.record, null),
                        )
                      : null,
                  icon: const Icon(Icons.format_indent_decrease),
                  label: const Text('Move to top level'),
                ),
              OutlinedButton.icon(
                onPressed:
                    canEdit &&
                        widget.controller.calendars.any(
                          (calendar) =>
                              !calendar.isReadOnly &&
                              calendar.id != task.calendarId,
                        )
                    ? () => unawaited(_chooseCalendar(context))
                    : null,
                icon: const Icon(Icons.drive_file_move_outline),
                label: const Text('Move to another list'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _dateButton(
                context,
                label: 'Start',
                propertyName: 'DTSTART',
                current: task.start,
                canEdit: canEdit,
              ),
              _dateButton(
                context,
                label: 'Due',
                propertyName: 'DUE',
                current: task.due,
                canEdit: canEdit,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Priority', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _priorityChoice('None', null, canEdit),
              _priorityChoice('High', 1, canEdit),
              _priorityChoice('Medium', 5, canEdit),
              _priorityChoice('Low', 9, canEdit),
            ],
          ),
          const SizedBox(height: 12),
          Text('Status', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _statusChoice('To do', CloudTaskStatus.needsAction, canEdit),
              _statusChoice('In progress', CloudTaskStatus.inProcess, canEdit),
              _statusChoice('Completed', CloudTaskStatus.completed, canEdit),
              _statusChoice('Cancelled', CloudTaskStatus.cancelled, canEdit),
              _statusChoice('Not set', null, canEdit),
            ],
          ),
          if (task.isCompleted) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(
                  task.completedAt == null
                      ? 'Set completion date'
                      : 'Completed ${_timestampLabel(task.completedAt!)}',
                ),
                onSelected: canEdit
                    ? (_) => unawaited(_pickCompletionDate(context))
                    : null,
                onDeleted: canEdit && task.completedAt != null
                    ? () => unawaited(
                        widget.controller.updateCompletedAt(
                          widget.record,
                          null,
                        ),
                      )
                    : null,
                deleteIcon: task.completedAt == null
                    ? null
                    : const Icon(Icons.close, size: 18),
              ),
            ),
          ],
          Row(
            children: <Widget>[
              const Text('Progress'),
              Expanded(
                child: Slider(
                  value: _progressDraft,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${_progressDraft.round()}%',
                  onChanged: canEdit
                      ? (value) => setState(() => _progressDraft = value)
                      : null,
                  onChangeEnd: canEdit
                      ? (value) => unawaited(
                          widget.controller.updateProgress(
                            widget.record,
                            value.round(),
                          ),
                        )
                      : null,
                ),
              ),
              SizedBox(width: 42, child: Text('${_progressDraft.round()}%')),
            ],
          ),
          const SizedBox(height: 8),
          Text('Repeat', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (task.recurrenceRule != null)
                Chip(label: Text(_recurrenceLabel(task.recurrenceRule))),
              OutlinedButton.icon(
                onPressed: canEdit && (task.start != null || task.due != null)
                    ? () => unawaited(_editRecurrence(context))
                    : null,
                icon: const Icon(Icons.repeat),
                label: Text(
                  task.recurrenceRule == null ? 'Add repeat' : 'Edit repeat',
                ),
              ),
            ],
          ),
          if (task.start == null && task.due == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Set a start or due date before adding recurrence.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          Text('Reminders', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final reminder in task.reminders)
                Chip(label: Text(_reminderLabel(context, reminder))),
              OutlinedButton.icon(
                onPressed: canEdit
                    ? () => unawaited(_manageReminders(context))
                    : null,
                icon: const Icon(Icons.notifications_outlined),
                label: Text(
                  task.reminders.isEmpty ? 'Add reminders' : 'Manage reminders',
                ),
              ),
            ],
          ),
          if (task.start == null && task.due == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Set a start or due date before adding a relative reminder.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          _CommitTextField(
            value: task.location ?? '',
            label: 'Location',
            icon: Icons.place_outlined,
            enabled: writable,
            readOnly: !canEdit,
            onCommit: (value) =>
                widget.controller.updateLocation(widget.record, value),
          ),
          const SizedBox(height: 10),
          _CommitTextField(
            value: task.url?.toString() ?? '',
            label: 'Related link',
            icon: Icons.link,
            enabled: writable,
            readOnly: !canEdit,
            keyboardType: TextInputType.url,
            onCommit: (value) =>
                widget.controller.updateUrl(widget.record, value),
          ),
          if (task.url != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => unawaited(
                  launchUrl(task.url!, mode: LaunchMode.externalApplication),
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open link'),
              ),
            ),
          const SizedBox(height: 12),
          Text('Privacy', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _privacyChoice('Default', null, canEdit),
              _privacyChoice('Public', CloudTaskPrivacy.public, canEdit),
              _privacyChoice('Private', CloudTaskPrivacy.private, canEdit),
              _privacyChoice(
                'Confidential',
                CloudTaskPrivacy.confidential,
                canEdit,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TagEditor(
            record: widget.record,
            controller: widget.controller,
            canEdit: canEdit,
          ),
          if (canEdit) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  onPressed: () => unawaited(
                    widget.controller.updatePinned(widget.record, !task.pinned),
                  ),
                  icon: Icon(
                    task.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  label: Text(task.pinned ? 'Unpin task' : 'Pin task'),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(
                    widget.controller.duplicateTaskTree(widget.record),
                  ),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(
                    widget.controller.descendantCount(widget.record) == 0
                        ? 'Duplicate task'
                        : 'Duplicate task and subtasks',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_confirmDelete(context)),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete task'),
                ),
              ],
            ),
          ],
          const Divider(height: 24),
          Text(
            _taskMetadataLabel(task),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _dateButton(
    BuildContext context, {
    required String label,
    required String propertyName,
    required CloudTaskDate? current,
    required bool canEdit,
  }) {
    return InputChip(
      avatar: const Icon(Icons.event_outlined, size: 18),
      label: Text(
        current == null ? 'Set $label date' : '$label ${_dateLabel(current)}',
      ),
      onSelected: canEdit
          ? (_) => unawaited(_pickDate(context, propertyName, current))
          : null,
      onDeleted: canEdit && current != null
          ? () => unawaited(
              widget.controller.updateTaskDate(
                widget.record,
                propertyName,
                null,
              ),
            )
          : null,
      deleteIcon: current == null ? null : const Icon(Icons.close, size: 18),
    );
  }

  Widget _priorityChoice(String label, int? value, bool canEdit) {
    return ChoiceChip(
      label: Text(label),
      selected:
          widget.record.task.priority == value ||
          (value == null && (widget.record.task.priority ?? 0) == 0),
      onSelected: canEdit
          ? (_) => unawaited(
              widget.controller.updatePriority(widget.record, value),
            )
          : null,
    );
  }

  Widget _statusChoice(String label, CloudTaskStatus? value, bool canEdit) {
    final selected = widget.record.task.status == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: canEdit
          ? (isSelected) {
              if (isSelected && !selected) {
                unawaited(widget.controller.updateStatus(widget.record, value));
              }
            }
          : null,
    );
  }

  Widget _privacyChoice(String label, CloudTaskPrivacy? value, bool canEdit) {
    return ChoiceChip(
      label: Text(label),
      selected: widget.record.task.privacy == value,
      onSelected: canEdit && widget.controller.canEditPrivacy(widget.record)
          ? (_) =>
                unawaited(widget.controller.updatePrivacy(widget.record, value))
          : null,
    );
  }

  Future<void> _chooseParent(BuildContext context) async {
    const rootChoice = '__cloud_tasks_root__';
    final candidates = widget.controller.availableParentsFor(widget.record);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Text(
                    'Choose a parent task',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.vertical_align_top),
                        title: const Text('Top level'),
                        selected: widget.record.task.parentUid == null,
                        onTap: () => Navigator.pop(context, rootChoice),
                      ),
                      for (final candidate in candidates)
                        ListTile(
                          leading: const Icon(Icons.task_alt_outlined),
                          title: Text(candidate.task.summary),
                          subtitle: candidate.task.parentUid == null
                              ? null
                              : const Text('Subtask'),
                          selected:
                              widget.record.task.parentUid ==
                              candidate.task.uid,
                          onTap: () =>
                              Navigator.pop(context, candidate.task.uid),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      await widget.controller.reparentTask(
        widget.record,
        selected == rootChoice ? null : selected,
      );
    }
  }

  Future<void> _chooseCalendar(BuildContext context) async {
    final choices = widget.controller.calendars
        .where(
          (calendar) =>
              widget.controller.canMoveRecordTo(widget.record, calendar),
        )
        .toList(growable: false);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(
                'Move task to another list',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            for (final calendar in choices)
              ListTile(
                leading: Icon(
                  Icons.checklist,
                  color: _calendarColor(calendar.color),
                ),
                title: Text(calendar.displayName),
                subtitle: Text(
                  widget.controller.descendantCount(widget.record) == 0
                      ? 'Move this task'
                      : 'Move this task and its subtasks',
                ),
                onTap: () => Navigator.pop(context, calendar.id),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected != null) {
      await widget.controller.moveTaskTree(widget.record, selected);
    }
  }

  Future<void> _editRecurrence(BuildContext context) async {
    final task = widget.record.task;
    final anchor = (task.start ?? task.due)?.value.toLocal();
    if (anchor == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => RecurrenceEditor(
        currentRule: task.recurrenceRule,
        anchor: anchor,
        onSave: (rule) =>
            unawaited(widget.controller.updateRecurrence(widget.record, rule)),
      ),
    );
  }

  Future<void> _pickCompletionDate(BuildContext context) async {
    final now = DateTime.now();
    final current = widget.record.task.completedAt?.toLocal() ?? now;
    final firstDate = DateTime(1970);
    final initialDate = current.isBefore(firstDate)
        ? firstDate
        : current.isAfter(now)
        ? now
        : current;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (selectedDate == null || !context.mounted) {
      return;
    }
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (selectedTime == null || !context.mounted) {
      return;
    }
    final completedAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    if (completedAt.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completion date must not be in the future.'),
        ),
      );
      return;
    }
    await widget.controller.updateCompletedAt(widget.record, completedAt);
  }

  Future<void> _pickDate(
    BuildContext context,
    String propertyName,
    CloudTaskDate? current,
  ) async {
    final firstDate = DateTime(1970);
    final lastDate = DateTime(2100, 12, 31);
    final requestedInitialDate = current?.value.toLocal() ?? DateTime.now();
    final initialDate = requestedInitialDate.isBefore(firstDate)
        ? firstDate
        : requestedInitialDate.isAfter(lastDate)
        ? lastDate
        : requestedInitialDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (selected == null || !context.mounted) {
      return;
    }
    final useTime = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Date precision',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.today_outlined),
                title: const Text('All day'),
                subtitle: const Text('Synchronize a date without a time'),
                onTap: () => Navigator.pop(context, false),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Set a time'),
                subtitle: const Text('Use this device’s local time'),
                onTap: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (useTime == null || !context.mounted) {
      return;
    }
    var value = selected;
    if (useTime) {
      final initialTime = current != null && !current.isAllDay
          ? TimeOfDay.fromDateTime(current.value.toLocal())
          : TimeOfDay.now();
      final time = await showTimePicker(
        context: context,
        initialTime: initialTime,
      );
      if (time == null) {
        return;
      }
      value = DateTime(
        selected.year,
        selected.month,
        selected.day,
        time.hour,
        time.minute,
      );
    }
    await widget.controller.updateTaskDate(
      widget.record,
      propertyName,
      CloudTaskDate(value: value, isAllDay: !useTime),
    );
  }

  Future<void> _manageReminders(BuildContext context) async {
    final task = widget.record.task;
    final choices = <CloudTaskReminder>[
      if (task.start != null) ...const <CloudTaskReminder>[
        CloudTaskReminder(trigger: 'PT0S', relatedToEnd: false),
        CloudTaskReminder(trigger: '-PT15M', relatedToEnd: false),
        CloudTaskReminder(trigger: '-PT1H', relatedToEnd: false),
        CloudTaskReminder(trigger: '-P1D', relatedToEnd: false),
      ],
      if (task.due != null) ...const <CloudTaskReminder>[
        CloudTaskReminder(trigger: 'PT0S', relatedToEnd: true),
        CloudTaskReminder(trigger: '-PT15M', relatedToEnd: true),
        CloudTaskReminder(trigger: '-PT1H', relatedToEnd: true),
        CloudTaskReminder(trigger: '-P1D', relatedToEnd: true),
      ],
    ];
    final selected = List<CloudTaskReminder>.of(task.reminders);
    final result = await showModalBottomSheet<List<CloudTaskReminder>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          bool contains(CloudTaskReminder candidate) => selected.any(
            (item) =>
                item.trigger == candidate.trigger &&
                item.relatedToEnd == candidate.relatedToEnd,
          );
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: Text(
                      'Task reminders',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        for (final choice in choices)
                          CheckboxListTile(
                            value: contains(choice),
                            title: Text(_reminderLabel(context, choice)),
                            onChanged: (enabled) => setSheetState(() {
                              if (enabled ?? false) {
                                if (!contains(choice)) {
                                  selected.add(choice);
                                }
                              } else {
                                selected.removeWhere(
                                  (item) =>
                                      item.trigger == choice.trigger &&
                                      item.relatedToEnd == choice.relatedToEnd,
                                );
                              }
                            }),
                          ),
                        ListTile(
                          leading: const Icon(Icons.add_alarm_outlined),
                          title: const Text('Add specific date and time'),
                          subtitle: const Text(
                            'Create an absolute reminder independent of start '
                            'or due dates',
                          ),
                          onTap: () async {
                            final now = DateTime.now();
                            final date = await showDatePicker(
                              context: context,
                              initialDate: now,
                              firstDate: DateTime(now.year - 1),
                              lastDate: DateTime(now.year + 20),
                            );
                            if (date == null || !context.mounted) {
                              return;
                            }
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (time == null || !context.mounted) {
                              return;
                            }
                            final trigger = VTodoCodec.formatUtcDateTime(
                              DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              ).toUtc(),
                            );
                            final reminder = CloudTaskReminder(
                              trigger: trigger,
                              relatedToEnd: false,
                              description: 'Task reminder',
                            );
                            setSheetState(() {
                              if (!contains(reminder)) {
                                selected.add(reminder);
                              }
                            });
                          },
                        ),
                        for (final reminder in selected.where(
                          (item) => !choices.any(
                            (choice) =>
                                choice.trigger == item.trigger &&
                                choice.relatedToEnd == item.relatedToEnd,
                          ),
                        ))
                          ListTile(
                            leading: const Icon(Icons.tune),
                            title: Text(_reminderLabel(context, reminder)),
                            subtitle: Text(
                              _parseAbsoluteReminder(reminder.trigger) == null
                                  ? 'Custom alarm retained from Nextcloud'
                                  : 'Specific date and time',
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove reminder',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => setSheetState(
                                () => selected.remove(reminder),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, selected),
                      child: const Text('Save reminders'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result != null) {
      await widget.controller.updateReminders(widget.record, result);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final descendants = widget.controller.descendantCount(widget.record);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Delete “${widget.record.task.summary}”?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  descendants == 0
                      ? 'This removes the task from Nextcloud and every '
                            'synced device.'
                      : 'This also removes $descendants '
                            '${descendants == 1 ? 'subtask' : 'subtasks'} from '
                            'Nextcloud and every synced device.',
                ),
                const SizedBox(height: 20),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete task'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed ?? false) {
      await widget.controller.deleteTask(widget.record);
    }
  }

  void _onTitleFocusChanged() {
    if (!_titleFocus.hasFocus) {
      final summary = _titleController.text.trim();
      if (summary.isEmpty) {
        _titleController.text = widget.record.task.summary;
      } else {
        unawaited(widget.controller.updateSummary(widget.record, summary));
      }
    }
  }

  void _onDescriptionFocusChanged() {
    if (!_descriptionFocus.hasFocus) {
      unawaited(
        widget.controller.updateDescription(
          widget.record,
          _descriptionController.text,
        ),
      );
    }
  }
}

class _CommitTextField extends StatefulWidget {
  const _CommitTextField({
    required this.value,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.readOnly,
    required this.onCommit,
    this.keyboardType,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool enabled;
  final bool readOnly;
  final TextInputType? keyboardType;
  final Future<void> Function(String value) onCommit;

  @override
  State<_CommitTextField> createState() => _CommitTextFieldState();
}

class _CommitTextFieldState extends State<_CommitTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _CommitTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      keyboardType: widget.keyboardType,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _focusNode.unfocus(),
      onTapOutside: (_) => _focusNode.unfocus(),
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon),
        border: const OutlineInputBorder(),
      ),
    );
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      unawaited(widget.onCommit(_controller.text));
    }
  }
}

class _TagEditor extends StatefulWidget {
  const _TagEditor({
    required this.record,
    required this.controller,
    required this.canEdit,
  });

  final TaskRecord record;
  final CloudTasksController controller;
  final bool canEdit;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.record.task.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Tags', style: Theme.of(context).textTheme.labelLarge),
        if (categories.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final category in categories)
                InputChip(
                  label: Text(category),
                  onDeleted: widget.canEdit
                      ? () => unawaited(
                          widget.controller.updateCategories(
                            widget.record,
                            categories.where((item) => item != category),
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ],
        if (widget.canEdit) ...<Widget>[
          if (widget.controller.availableTags.any(
            (tag) => !categories.contains(tag),
          )) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final tag
                    in widget.controller.availableTags
                        .where((tag) => !categories.contains(tag))
                        .take(8))
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(tag),
                    onPressed: () => unawaited(
                      widget.controller.updateCategories(
                        widget.record,
                        <String>[...categories, tag],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addTag(),
            decoration: InputDecoration(
              hintText: 'Add a tag',
              prefixIcon: const Icon(Icons.sell_outlined),
              suffixIcon: IconButton(
                tooltip: 'Add tag',
                onPressed: _addTag,
                icon: const Icon(Icons.add),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  void _addTag() {
    final value = _controller.text.trim();
    if (value.isEmpty || widget.record.task.categories.contains(value)) {
      return;
    }
    _controller.clear();
    unawaited(
      widget.controller.updateCategories(widget.record, <String>[
        ...widget.record.task.categories,
        value,
      ]),
    );
  }
}

int _taskNodeCount(Iterable<TaskHierarchyNode> nodes) {
  var count = 0;
  for (final node in nodes) {
    count += 1 + _taskNodeCount(node.children);
  }
  return count;
}

int _closedTaskNodeCount(Iterable<TaskHierarchyNode> nodes) {
  var count = 0;
  for (final node in nodes) {
    if (node.task.isClosed) {
      count++;
    }
    count += _closedTaskNodeCount(node.children);
  }
  return count;
}

String _taskMetadataLabel(CloudTask task) {
  final parts = <String>[];
  if (task.createdAt != null) {
    parts.add('Created ${_timestampLabel(task.createdAt!)}');
  }
  if (task.lastModifiedAt != null) {
    parts.add('Modified ${_timestampLabel(task.lastModifiedAt!)}');
  }
  if (task.completedAt != null) {
    parts.add('Completed ${_timestampLabel(task.completedAt!)}');
  }
  return parts.isEmpty
      ? 'No timestamp metadata supplied by the server.'
      : parts.join(' • ');
}

String _timestampLabel(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

Color? _calendarColor(String? source) {
  if (source == null) {
    return null;
  }
  final hex = source.replaceAll('#', '').trim();
  if (hex.length != 6 && hex.length != 8) {
    return null;
  }
  final rgb = int.tryParse(hex.substring(0, 6), radix: 16);
  final alpha = hex.length == 8
      ? int.tryParse(hex.substring(6, 8), radix: 16)
      : 255;
  if (rgb == null || alpha == null) {
    return null;
  }
  return Color((alpha << 24) | rgb);
}

String _dateLabel(CloudTaskDate date) {
  final value = date.value.isUtc ? date.value.toLocal() : date.value;
  final day = '${value.month}/${value.day}/${value.year}';
  if (date.isAllDay) {
    return day;
  }
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '$day $hour:$minute $period';
}

String _priorityLabel(int? priority) {
  if (priority == null || priority == 0) {
    return 'No priority';
  }
  if (priority <= 4) {
    return 'High';
  }
  if (priority == 5) {
    return 'Medium';
  }
  return 'Low';
}

int _taskProgress(CloudTask task) {
  if (task.isCompleted) {
    return 100;
  }
  final value = task.percentComplete ?? 0;
  if (value < 0) {
    return 0;
  }
  if (value > 100) {
    return 100;
  }
  return value;
}

String _recurrenceLabel(String? rule) {
  if (rule == null) {
    return 'Does not repeat';
  }
  final parts = <String, String>{};
  for (final part in rule.split(';')) {
    final separator = part.indexOf('=');
    if (separator > 0) {
      parts[part.substring(0, separator)] = part.substring(separator + 1);
    }
  }
  final interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
  final unit = switch (parts['FREQ']) {
    'DAILY' => interval == 1 ? 'Daily' : 'Every $interval days',
    'WEEKLY' => interval == 1 ? 'Weekly' : 'Every $interval weeks',
    'MONTHLY' => interval == 1 ? 'Monthly' : 'Every $interval months',
    'YEARLY' => interval == 1 ? 'Yearly' : 'Every $interval years',
    _ => 'Custom repeat',
  };
  return unit;
}

String _reminderLabel(BuildContext context, CloudTaskReminder? reminder) {
  if (reminder == null) {
    return 'No reminder';
  }
  final anchor = reminder.relatedToEnd ? 'due' : 'start';
  switch (reminder.trigger) {
    case 'PT0S':
      return 'At $anchor time';
    case '-PT15M':
      return '15 min before $anchor';
    case '-PT1H':
      return '1 hour before $anchor';
    case '-P1D':
      return '1 day before $anchor';
  }
  final absolute = _parseAbsoluteReminder(reminder.trigger);
  if (absolute != null) {
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(absolute)} at '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(absolute))}';
  }
  return 'Custom reminder';
}

DateTime? _parseAbsoluteReminder(String source) {
  final value = source.trim();
  if (!RegExp(r'^\d{8}T\d{6}Z?$').hasMatch(value)) {
    return null;
  }
  try {
    final parts = <int>[
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
      int.parse(value.substring(9, 11)),
      int.parse(value.substring(11, 13)),
      int.parse(value.substring(13, 15)),
    ];
    final date = value.endsWith('Z')
        ? DateTime.utc(
            parts[0],
            parts[1],
            parts[2],
            parts[3],
            parts[4],
            parts[5],
          )
        : DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    return date.toLocal();
  } on FormatException {
    return null;
  } on RangeError {
    return null;
  }
}
