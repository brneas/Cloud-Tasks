# Cloud Tasks

Cloud Tasks is a privacy-respecting, offline-first Android client for
[Nextcloud Tasks](https://apps.nextcloud.com/apps/tasks). It connects directly
to a user-selected Nextcloud server, includes no analytics or advertising, and
keeps manual task order synchronized with the Nextcloud web app.

Version **1.0.0+20** is the first stable release. The permanent Android
application ID is `org.tecdesigns.cloud_tasks` and the launcher name is
**Cloud Tasks**.

> Cloud Tasks is an independent community project. It is not affiliated with
> or endorsed by Nextcloud GmbH.

## Highlights

- Exact manual ordering through each task's `X-APPLE-SORT-ORDER` value,
  independently for root tasks and every subtask group.
- Fast local edits with durable, debounced CalDAV writeback. Multiple tasks can
  be completed without waiting for each network request.
- Offline SQLite cache, queued writes, ETag-protected updates, incremental sync
  tokens, and conflict detection.
- Lists-first navigation, collapsible Smart Views, remembered view and order
  settings, and a compact Completed section with **Restore all**.
- Full day-to-day task editing: notes, hierarchy, dates, priority, progress,
  status, completion time, recurrence, alarms, tags, location, URL, privacy,
  and pinning.
- Task-list creation, editing, ordering, deletion, and supported Nextcloud
  sharing controls.
- Native `.ics` import/export, unknown iCalendar-property preservation, and
  Android notifications for synchronized display alarms.
- Optional Android background sync with no project-operated relay service.

## Privacy

Cloud Tasks communicates only with the configured Nextcloud origin and links a
user explicitly opens. Login Flow v2 creates a revocable app password; the
normal account password is never entered into the app. Credentials use Android
secure storage and task data remains in the local offline cache or on the
configured server.

The app contains no analytics, advertising, telemetry, crash-reporting SDK, or
Google service integration. Markdown previews do not load remote images.
See [Security and privacy](docs/security.md) for the complete data-flow model.

## Requirements

- Flutter 3.44.0 or newer and Dart 3.12 or newer
- JDK 17
- A supported Nextcloud instance with at least one CalDAV task collection
- Android 7.0 (API 24) or newer

## Build from source

The public repository should include its generated `android/` project. If that
directory is absent from a source snapshot, generate it once with the final
organization ID:

```bash
flutter create --platforms=android --org org.tecdesigns .
```

Then complete the one-time identity, manifest, notification, and backup steps
in [Android setup](docs/android-notifications.md). Do not regenerate an existing
configured `android/` directory during a normal build.

```bash
flutter clean
flutter pub get
dart run flutter_launcher_icons
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter run
```

Commit the generated `pubspec.lock` for reproducible application builds. Never
edit `GeneratedPluginRegistrant.java`; `flutter clean` and `flutter pub get`
regenerate plugin registration from the resolved dependency graph.

For a signed APK, follow [Build and publish a release](docs/releasing.md). It
covers signing-key custody, APK verification, checksums, Git tags, and GitHub
Releases without using the Play Store.

## Connect to Nextcloud

1. Enter the HTTPS base URL of the Nextcloud instance, including any URL
   subpath.
2. Approve Cloud Tasks in the system browser and return to the app.
3. Select a list or Smart View. Use the bottom composer to add tasks, tap a
   title to edit it, and drag the handle while using manual order.
4. If the web app shows the opposite manual-order direction, choose the other
   direction in Cloud Tasks. The synchronized numeric positions remain valid.

The app discovers the account principal, CalDAV home, task lists, privileges,
and sync capabilities instead of constructing version-specific server paths.
Disconnecting removes the app password and that account's local cache; it does
not delete server data or revoke the app password on the server.

## Ordering and synchronization

Nextcloud's manual position is stored in each `VTODO` as an integer:

```text
X-APPLE-SORT-ORDER:1048576
```

Cloud Tasks treats this as synchronized task data. Parent/child relationships
and sibling order are separate, so reordering one subtask branch does not
disturb another.

Edits commit to SQLite before the network request starts. A short debounce
coalesces rapid changes, while conditional CalDAV writes prevent silent
overwrites. Interrupted writes remain queued. Changes to unrelated fields merge
automatically; if two clients change the same field differently, Cloud Tasks
keeps the server value and asks the user to apply the local change again.

## Compatibility and limitations

Cloud Tasks targets portable CalDAV and RFC 5545 behavior rather than one
hard-coded Nextcloud version. The 1.0 implementation was audited against
Nextcloud Tasks 0.18.1; see the [compatibility matrix](docs/compatibility.md) and
[functionality audit](docs/nextcloud-tasks-audit.md).

- Nextcloud Calendar trash is not exposed through CalDAV. Restore, permanent
  deletion, and empty-trash actions remain in the Calendar web app.
- Share recipients require an exact username or group ID because Nextcloud's
  autocomplete endpoint is not a portable CalDAV capability.
- Smart Views and non-manual sorts are local presentation features. Manual
  order is the interoperable ordering source of truth.

## Project documentation

| Document | Purpose |
| --- | --- |
| [Android setup](docs/android-notifications.md) | Identity, permissions, notifications, and backup settings |
| [Architecture](docs/architecture.md) | Layer boundaries, storage, synchronization, and merging |
| [Compatibility](docs/compatibility.md) | CalDAV behavior and supported interoperability |
| [Manual ordering](docs/nextcloud-ordering.md) | Position values, direction, hierarchy, and reindexing |
| [Sharing](docs/nextcloud-sharing.md) | Capabilities, ownership, and privacy rules |
| [Data portability](docs/data-portability.md) | Import, export, deletion, and Calendar trash |
| [Release guide](docs/releasing.md) | Secure signing and direct APK distribution |
| [Release checklist](docs/release-checklist.md) | Final validation before tagging 1.0.0 |
| [1.0.0 release notes](docs/release-notes-1.0.0.md) | User-facing release summary |

## Contributing and security

Bug reports and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md)
before submitting changes. Please report security issues privately according to
[SECURITY.md](SECURITY.md), without attaching real credentials or task data.

## License

Cloud Tasks is free software licensed under
[GNU GPL v3 or later](LICENSE). Copyright © 2026 Cloud Tasks contributors.
