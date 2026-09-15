import 'package:cloud_tasks/src/account/account_store.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_controller.dart';
import 'package:cloud_tasks/src/app/cloud_tasks_preferences.dart';
import 'package:cloud_tasks/src/data/sqlite_task_store.dart';
import 'package:cloud_tasks/src/notifications/task_notification_scheduler.dart';
import 'package:cloud_tasks/src/screens/cloud_tasks_home_screen.dart';
import 'package:cloud_tasks/src/sync/background_sync_scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class CloudTasksApp extends StatefulWidget {
  const CloudTasksApp({super.key, this.controller});

  final CloudTasksController? controller;

  @override
  State<CloudTasksApp> createState() => _CloudTasksAppState();
}

class _CloudTasksAppState extends State<CloudTasksApp> {
  late final CloudTasksController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        CloudTasksController(
          accountStore: SecureAccountStore(),
          taskStore: SqliteTaskStore(),
          browserLauncher: (url) =>
              launchUrl(url, mode: LaunchMode.externalApplication),
          notificationScheduler: AndroidTaskNotificationScheduler(),
          backgroundSyncScheduler: const WorkmanagerBackgroundSyncScheduler(),
        );
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) => MaterialApp(
        title: 'Cloud Tasks',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const <Locale>[Locale('en')],
        themeMode: switch (_controller.preferences.theme) {
          CloudTasksTheme.system => ThemeMode.system,
          CloudTasksTheme.light => ThemeMode.light,
          CloudTasksTheme.dark => ThemeMode.dark,
        },
        theme: _cloudTasksTheme(Brightness.light),
        darkTheme: _cloudTasksTheme(Brightness.dark),
        home: CloudTasksHomeScreen(controller: _controller),
      ),
    );
  }
}

ThemeData _cloudTasksTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff0082c9),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: scheme.surfaceTint,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
    ),
  );
}
