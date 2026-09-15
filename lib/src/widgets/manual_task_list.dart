import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/ordering/manual_order_service.dart';
import 'package:flutter/material.dart';

class ManualTaskList extends StatefulWidget {
  const ManualTaskList({required this.initialTasks, super.key});

  final List<CloudTask> initialTasks;

  @override
  State<ManualTaskList> createState() => _ManualTaskListState();
}

class _ManualTaskListState extends State<ManualTaskList> {
  static const _ordering = ManualOrderService();
  late List<CloudTask> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = _ordering.sort(widget.initialTasks);
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: true,
      itemCount: _tasks.length,
      onReorder: _reorder,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return ListTile(
          key: ValueKey<String>(task.uid),
          leading: const Icon(Icons.radio_button_unchecked),
          title: Text(task.summary),
          subtitle: Text('X-APPLE-SORT-ORDER: ${task.sortOrder}'),
          trailing: const Icon(Icons.drag_handle),
        );
      },
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _tasks = _ordering.reorder(_tasks, oldIndex, newIndex);
    });
  }
}
