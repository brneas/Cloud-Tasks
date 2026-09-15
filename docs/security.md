# Security and privacy model

Cloud Tasks connects directly to the Nextcloud URL chosen by the user. It has
no analytics SDK, advertising SDK, crash-reporting service, telemetry endpoint
or project-operated relay.

The model protects credentials and task data from unnecessary third parties. It
does not protect a device that is already compromised, a malicious Nextcloud
server administrator, or data deliberately exported to another application.

## Credentials and transport

- Login Flow v2 creates a revocable per-client app password; the normal account
  password is never entered into Cloud Tasks.
- The server URL must use HTTPS. Redirects are constrained to the original
  origin by the DAV networking layer.
- Account details and the app password use platform secure storage. They are
  not written to SQLite, exported with tasks or included in error messages.
- Android backup should be disabled as described in
  [Android setup](android-notifications.md), preventing backup transport from
  copying local cache or secure-storage metadata.

## Local and background data

SQLite contains calendars, raw task documents, ETags and queued writes. This is
necessary for offline use and conflict-safe synchronization. Disconnecting an
account removes its credentials and cached content from the app database.

Foreground edits are committed locally before their direct CalDAV upload runs
in the background. The short debounce coalesces rapid edits and sends no task
data anywhere except the configured Nextcloud origin.

Automatic synchronization is off by default. When enabled, Android WorkManager
runs the same direct-to-Nextcloud synchronization with a connected-network
constraint. Android controls the exact execution time. No task contents or
credentials are placed in WorkManager input data.

## External content and files

Markdown note previews do not fetch remote images. HTTP and HTTPS links open
only after a tap and are handed to the system browser. Imports use Android's
document provider. Exports use the system share sheet; data goes only to the
target explicitly chosen there.

## Release integrity

Official project APKs should be attached only to an immutable GitHub Release,
alongside a SHA-256 checksum, and signed with the same self-managed Android
release key. Users can compare the APK certificate and checksum with the values
published by the maintainer. The certificate fingerprint is public; the signing
key and `android/key.properties` must never enter the repository, build logs,
CI secrets for untrusted pull requests, or release archives.

The public Git tag should contain the configured Android project and
`pubspec.lock` used for the build. GitHub Actions are limited to read-only
repository permission and third-party actions are pinned to immutable commits.

## Reporting a vulnerability

Follow the private process in [SECURITY.md](../SECURITY.md). Do not include real
server URLs, app passwords, task documents, signing material, or database files
in a public report. Provide a minimal reproduction with redacted fixtures and
identify the affected Cloud Tasks, Flutter, Android, and Nextcloud versions.
