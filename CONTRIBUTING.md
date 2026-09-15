# Contributing to Cloud Tasks

Thank you for helping improve Cloud Tasks. Bug reports, protocol fixtures,
documentation, accessibility improvements, and focused pull requests are
welcome.

## Before opening an issue

- Search existing issues and test the latest release or default branch.
- For a bug, include the Cloud Tasks, Flutter, Android, and Nextcloud versions,
  the expected result, the actual result, and minimal reproduction steps.
- Redact server names, usernames, app passwords, task content, calendar URLs,
  ETags, and database files.
- Report potential vulnerabilities privately through [SECURITY.md](SECURITY.md).

## Development setup

Use Flutter 3.44.0 or newer, Dart 3.12 or newer, and JDK 17. If the Android
directory is absent, generate it with the permanent application identity:

```bash
flutter create --platforms=android --org org.tecdesigns .
flutter pub get
dart run flutter_launcher_icons
```

Complete [the Android setup](docs/android-notifications.md), then validate every
change:

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

Add tests for changed behavior. CalDAV and iCalendar regressions should use the
smallest possible synthetic fixture; never commit content copied from a real
account.

## Pull requests

- Keep each pull request focused and explain user-visible behavior.
- Preserve unknown iCalendar properties and conditional-write protections.
- Do not add telemetry, advertising, a project relay, or a required third-party
  account.
- Do not edit generated plugin registration by hand.
- Update `CHANGELOG.md` and relevant documentation for user-visible changes.
- Confirm formatting, analysis, and all tests pass before requesting review.

By contributing, you agree that your contribution is licensed under
GPL-3.0-or-later.
