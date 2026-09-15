# Android platform setup

Cloud Tasks schedules each synchronized display alarm as an inexact Android
alarm. Inexact delivery avoids the privileged exact-alarm permission while
still allowing reminders during idle periods. Android 13 and newer asks for
the normal notification permission when the first future reminder is found.

The permanent Android identity is `org.tecdesigns.cloud_tasks`; the launcher
name is **Cloud Tasks**. For a new platform directory, generate it once with:

```bash
flutter create --platforms=android --org org.tecdesigns .
```

If `android/` already exists, do not recreate it. Instead, verify
`namespace = "org.tecdesigns.cloud_tasks"` and
`applicationId = "org.tecdesigns.cloud_tasks"` in
`android/app/build.gradle.kts`. The package declaration and directory for
`MainActivity.kt` must also be `org.tecdesigns.cloud_tasks`, and the
`<application>` label in `AndroidManifest.xml` must be `Cloud Tasks`.

Commit the configured Android project to the public repository, but never
commit `android/key.properties`, `local.properties`, a signing key, or a built
APK. See [the release guide](releasing.md) for signed-build configuration.

## 1. Gradle and identity

In `android/app/build.gradle.kts`, ensure the Android block uses at least API
35 and enables core-library desugaring:

```kotlin
android {
    compileSdk = 35

    defaultConfig {
        multiDexEnabled = true
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Keep a higher `compileSdk` if the installed Flutter SDK already generated one.
WorkManager 0.10 requires JDK 17, so do not lower the Java or Kotlin target.
If the project uses Groovy instead, use the equivalent
`coreLibraryDesugaringEnabled true` and
`coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'` syntax.

## 2. Manifest permissions and receivers

Add these permissions directly inside `<manifest>` in
`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

Add these receivers directly inside `<application>` so future alarms survive
a reboot or application update:

```xml
<receiver
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
    android:exported="false" />
<receiver
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
    android:exported="false">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
    </intent-filter>
</receiver>
```

No `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM` permission is required.

The optional automatic-sync setting uses Android WorkManager. Its receiver and
service declarations are merged from the maintained plugin automatically, so
no additional manifest component is required. The app submits no task data or
credentials as worker input and applies a connected-network constraint.

## 3. Privacy setting

Set `android:allowBackup="false"` and explicit extraction rules so cloud backup
and device-to-device transfer do not copy the local cache or secure-storage
metadata. The explicit rules also cover Android 12+ devices whose manufacturer
does not apply `allowBackup="false"` to device transfer.
See Android's [Auto Backup documentation](https://developer.android.com/identity/data/autobackup)
for the platform behavior behind these settings.

Keep the application label, icon, and backup policy explicit:

```xml
<application
    android:label="Cloud Tasks"
    android:icon="@mipmap/ic_launcher"
    android:allowBackup="false"
    android:fullBackupContent="@xml/backup_rules"
    android:dataExtractionRules="@xml/data_extraction_rules">
```

Create `android/app/src/main/res/xml/backup_rules.xml` for Android 11 and
earlier:

```xml
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <exclude domain="root" path="." />
    <exclude domain="file" path="." />
    <exclude domain="database" path="." />
    <exclude domain="sharedpref" path="." />
    <exclude domain="external" path="." />
    <exclude domain="device_root" path="." />
    <exclude domain="device_file" path="." />
    <exclude domain="device_database" path="." />
    <exclude domain="device_sharedpref" path="." />
</full-backup-content>
```

Create `android/app/src/main/res/xml/data_extraction_rules.xml` for Android 12
and newer:

```xml
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" path="." />
        <exclude domain="file" path="." />
        <exclude domain="database" path="." />
        <exclude domain="sharedpref" path="." />
        <exclude domain="external" path="." />
        <exclude domain="device_root" path="." />
        <exclude domain="device_file" path="." />
        <exclude domain="device_database" path="." />
        <exclude domain="device_sharedpref" path="." />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" path="." />
        <exclude domain="file" path="." />
        <exclude domain="database" path="." />
        <exclude domain="sharedpref" path="." />
        <exclude domain="external" path="." />
        <exclude domain="device_root" path="." />
        <exclude domain="device_file" path="." />
        <exclude domain="device_database" path="." />
        <exclude domain="device_sharedpref" path="." />
    </device-transfer>
</data-extraction-rules>
```

After these one-time changes, or after changing Flutter plugins, run:

```bash
flutter clean
flutter pub get
flutter test
flutter run
```

`flutter clean` makes Flutter regenerate `GeneratedPluginRegistrant.java` from
the resolved dependencies. Never edit that generated file by hand.
