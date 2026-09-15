# Release checklist

Complete this checklist for the exact commit and signed APK that will be
published. Detailed commands are in [Build and publish a release](releasing.md).

## Identity and source

- [ ] `pubspec.yaml` contains the intended version and a new build number.
- [ ] Android `namespace` and `applicationId` are
      `org.tecdesigns.cloud_tasks`.
- [ ] `MainActivity` uses the matching package and directory.
- [ ] The Android launcher label is `Cloud Tasks`.
- [ ] The configured `android/` directory and resolved `pubspec.lock` are
      committed.
- [ ] The full GPL-3.0 license, security policy, release notes, and current
      documentation are present.
- [ ] The working tree is clean and the tag will point to the tested commit.

## Secrets and supply chain

- [ ] `android/key.properties`, local SDK paths, keystores, private keys, APKs,
      databases, logs, exports, credentials, and real server data are not
      tracked anywhere in Git history.
- [ ] The release keystore is outside the repository with two separate,
      encrypted backups.
- [ ] The signing-certificate fingerprint is recorded, published, and matches
      earlier releases.
- [ ] Direct and transitive changes in `pubspec.lock` were reviewed.
- [ ] GitHub secret scanning, push protection, Dependabot alerts, and private
      vulnerability reporting are enabled.
- [ ] GitHub Actions use read-only permissions and immutable action commit
      references.

## Automated validation

- [ ] `flutter doctor -v` reports the intended Flutter SDK and JDK 17.
- [ ] `flutter clean` and `flutter pub get` succeed.
- [ ] `dart run flutter_launcher_icons` succeeds and the icon looks correct
      under common adaptive masks.
- [ ] `dart format --output=none --set-exit-if-changed .` passes.
- [ ] `flutter analyze` passes without warnings.
- [ ] `flutter test` passes completely.
- [ ] The GitHub validation workflow passes on the release commit.

## Android and migration

- [ ] The manifest contains only expected permissions and components.
- [ ] Android backup and device transfer are disabled with both legacy and
      Android 12+ rules; no exact-alarm permission or tracker SDK is present.
- [ ] An earlier release upgrades without losing lists, task order, credentials,
      queued writes, default list, or device preferences.
- [ ] An interrupted edit survives restart and uploads after reconnecting.
- [ ] At least ten tasks can be completed quickly while upload is active.
- [ ] Offline complete/restore actions coalesce to the correct final state.
- [ ] An interrupted cross-list subtree move never deletes the source before
      every destination object exists.
- [ ] An invalid sync token recovers through a full query.

## Nextcloud parity

- [ ] Login works for both a base-domain install and an instance below a URL
      path.
- [ ] Root-task and subtask manual order match Nextcloud Tasks in both display
      directions.
- [ ] **Restore all** preserves hierarchy and manual positions.
- [ ] The selected list or Smart View and order direction survive restart;
      temporary search/tag filters do not.
- [ ] Create, edit, complete, recur, remind, reorder, move, duplicate, import,
      export, and delete agree with the web app.
- [ ] Pinning, cleared status, completion dates, priority, privacy, and Smart
      View membership agree with the web app.
- [ ] Owned, shared writable, and shared read-only lists behave correctly.
- [ ] PRIVATE and CONFIDENTIAL tasks received through a share remain read-only.
- [ ] Enabled background sync receives a server-side change; disabling it
      cancels periodic work.

## Signed artifact

- [ ] The release APK is signed with the release key, not the debug key.
- [ ] `apksigner verify --verbose --print-certs` succeeds and reports the
      expected certificate.
- [ ] The exact APK installs on a clean device and passes a release-mode smoke
      test.
- [ ] SHA-256 checksums were generated after the final build and match a fresh
      download from GitHub Releases.
- [ ] The immutable `v1.0.0` tag, release notes, APK, `SHA256SUMS.txt`, and
      published certificate fingerprint all refer to the same build.
