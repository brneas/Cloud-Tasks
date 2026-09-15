# Cloud Tasks 1.0.0 release notes

Cloud Tasks is an Android-first, privacy-respecting and offline-first client for
Nextcloud Tasks. It connects directly to the user's server and synchronizes the
same manual task positions used by the Nextcloud web app.

The Android application ID is `org.tecdesigns.cloud_tasks`. Directly distributed
APKs are signed by the project maintainer and are intended to be installed or
updated without Google Play.

## Highlights

- Exact `X-APPLE-SORT-ORDER` synchronization for root tasks and subtasks.
- Fast local editing with durable, debounced background CalDAV writeback.
- Lists-first navigation, collapsible Smart Views and a compact Completed
  section with Restore all.
- Notes, dates, priority, progress, status, completion time, recurrence,
  reminders, tags, location, links, privacy and pinning.
- Task-list creation, editing, ordering and supported Nextcloud sharing.
- Offline queueing, conditional writes, conflict detection and incremental
  sync-token refreshes.
- Native `.ics` import/export and Android notification scheduling.
- No analytics, advertising, telemetry or project-operated network service.
- Public build instructions, security policy, dependency update configuration,
  immutable CI action references, and signed-APK verification guidance.

## Requirements

- Android build generated with Flutter 3.44.0 or newer, Dart 3.12 or newer and
  JDK 17.
- A supported Nextcloud instance with a CalDAV task collection.
- The Android manifest and Gradle setup documented in
  `android-notifications.md`.

## Intentional limitations

- Nextcloud Calendar's trash is not exposed through CalDAV, so restoring or
  permanently deleting trashed tasks remains a web-app operation.
- Share recipients are entered by exact username or group ID because
  Nextcloud's autocomplete is not a portable CalDAV capability.
- Smart-view membership and non-manual sorts are local presentation features;
  manual task position is the interoperable ordering source of truth.

See `release-checklist.md` before signing or distributing a build.

Cloud Tasks is an independent community project and is not affiliated with or
endorsed by Nextcloud GmbH.
