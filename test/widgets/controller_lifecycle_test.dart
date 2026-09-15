import 'dart:async';

import 'package:cloud_tasks/src/widgets/cloud_task_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('calendar editor owns its controller through route dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => unawaited(
                showDialog<void>(
                  context: context,
                  builder: (_) => const CalendarEditorDialog(),
                ),
              ),
              child: const Text('Open calendar editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open calendar editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Personal');
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('share editor owns its controller through route dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => unawaited(
                showDialog<void>(
                  context: context,
                  builder: (_) => const ShareEditorDialog(),
                ),
              ),
              child: const Text('Open share editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open share editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'alice');
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
