# Changelog

## 1.0.0

- Updated the release toolchain to Flutter 3.44 and Dart 3.12 and migrated
  deprecated form, color and reorder APIs without changing manual-order
  behavior.
- Finalized the Android identity as `org.tecdesigns.cloud_tasks` with the
  launcher name Cloud Tasks.
- Added a secure direct-APK release guide, GitHub security policy, contribution
  guide, issue templates, automated dependency updates and pinned validation
  workflow.
- Hardened ignore rules for signing material, credentials, local Android
  configuration, release binaries and generated plugin registration.
- Reworked the README and release checklist for the stable public-source
  handoff.
- Commit task edits to the offline cache immediately and debounce their CalDAV
  upload in the background, keeping unrelated task controls responsive.
- Lock only tasks included in the active upload snapshot so a later edit cannot
  be lost when a pending write completes.
- Add a Restore all action to the completed-task section for reopening every
  completed task in the selected list without changing manual positions.
- Put task lists first in the navigation drawer and collapse Smart Views by
  default so large list collections stay easy to scan.
- Group completed tasks below active siblings in a collapsed section while
  preserving collision-free synchronized manual ordering during active-task
  drags.
- Add original Cloud Tasks launcher artwork and Android adaptive-icon
  generation configuration.
- Remember the last selected list or smart view and the chosen manual-order
  direction across app restarts.
- Replaced the ambiguous direction arrow with a clear manual-order sheet that
  explains how each option relates to Nextcloud's synchronized positions.
- Kept cached task lists visible during synchronization, with unobtrusive
  progress feedback instead of a blocking full-screen state.
- Refined navigation, empty states, task metadata and task cards for a calmer,
  more consistent Material 3 interface.
- Made the composer's primary add button submit immediately while keeping bulk
  creation in a separate overflow action.
- Removed misleading lock icons from editable smart and filtered views and hid
  raw internal sort-position numbers from normal task cards.
- Cached calendar, task, tag and descendant lookups to avoid repeated scans
  while rendering large or deeply nested lists.
- Guarded controller notifications after disposal and made task composers
  reliably leave their submitting state if an asynchronous operation fails.
- Added the version 5 cache migration for durable view preferences.
- Audited portable task behavior against Nextcloud Tasks 0.18.1.
- Added synchronized task pinning through Nextcloud's `X-PINNED` property.
- Added the Current smart view and aligned Today and Week membership with
  Nextcloud's start/due-date predicates.
- Added completion-date editing, future-date validation and status clearing.
- Treats a `COMPLETED` timestamp as completed even when a server omits STATUS.
- Enforced Nextcloud's privacy rules for non-public tasks in shared lists,
  including edit, classification and cross-list move restrictions.
- Added an Important smart view for active tasks with priority 1 through 4.
- Updated WorkManager for Flutter's AGP 9 build path and documented the Flutter,
  Dart and JDK 17 minimums.
- Fixed the settings widget test's missing Material import.
- Made controller initialization a single awaitable operation and removed
  startup-spinner `pumpAndSettle` timeouts from the signed-out widget tests.
- Isolated signed-out widget tests from the native SQLite FFI database so they
  cannot hang behind another test isolate's in-memory database connection.
- Deferred resolution of SQLite's platform database factory until the store
  actually opens a database, allowing database-free test doubles to remain
  database-free during construction.
- Added incremental CalDAV synchronization with sync-token expiry fallback.
- Added opt-in Android background sync, foreground intervals and resume sync.
- Added system, light and dark appearance settings.
- Made cross-list subtree moves resumable through phased pending operations.
- Added safe remote-deletion application that preserves dirty local records.
- Added a version 4 SQLite migration and task-status query index.
- Replaced `file_picker` with Flutter's maintained document selector for import
  and the Android share sheet for export.
- Fixed duplicate wildcard callback parameters on Dart versions before 3.7.
- Added task completion and reorder semantics for assistive technology.
- Added security, compatibility and release-validation documentation.

## 0.9.0

- Added productivity, metadata, Markdown preview, duplication, bulk creation,
  import/export, tag suggestions and completed-task cleanup features.
