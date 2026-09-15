# App icon

Cloud Tasks includes two original source assets under `assets/branding`:

- `cloud_tasks_icon.png` is the complete blue launcher icon used by legacy
  Android launchers.
- `cloud_tasks_icon_foreground.png` is the transparency-safe cloud and task
  mark used above Nextcloud blue (`#0082C9`) by adaptive launchers.

The cloud shape keeps the app visually compatible with a Nextcloud-centered
home screen, while the checkmark and list lines distinguish it from the
Nextcloud server and file apps. The design does not bundle or copy Nextcloud's
official logo asset.

After generating the Android platform directory, generate the launcher
resources from the configuration in `pubspec.yaml`:

```bash
flutter pub get
dart run flutter_launcher_icons
```

Do not hand-edit the generated mipmap or adaptive-icon XML files. Regenerate
them after changing either source PNG, changing the Android application ID or
recreating the platform directory.

The artwork is original to this project and is not an official Nextcloud logo.
Cloud Tasks is not affiliated with or endorsed by Nextcloud GmbH.
