# CliniqCare Production App Update & Release Guide

This document establishes the end-to-end release procedures for **CliniqCare**, including full APK distribution via GitHub Releases, in-app update checks governed by Cloud Firestore, and over-the-air (OTA) Dart code pushing via Shorebird.

---

## 1. Architecture Overview

CliniqCare uses a hybrid two-tier update architecture:

```
                          ┌─────────────────────────────┐
                          │   Cloud Firestore Metadata  │
                          │(app_config/updates_android) │
                          └──────────────┬──────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 ▼                                               ▼
       [Mechanism A: Full APK]                         [Mechanism B: OTA Patch]
    GitHub Releases APK Distribution                 Shorebird Code Push Runtime
   ──────────────────────────────────               ─────────────────────────────
   • Used for native changes, SDK upgrades,          • Used for Dart-only logic changes,
     engine upgrades, permissions, assets.             bug fixes, clinical workflow tweaks.
   • Downloads APK with progress bar.                • Runs seamlessly in background.
   • Prompts Android package installer.              • Takes effect upon next app restart.
   • Enforces mandatory blocking updates.            • Zero Play Store/APK reinstall needed.
```

---

## 2. Firestore Configuration Schema

- **Document Path:** `app_config/updates_android_production`
- **Security Rule:** Public unauthenticated read (strictly for `updates_android_production`), restricted write to `isMasterAdmin()`.

### Document Schema (JSON)

```json
{
  "platform": "android",
  "environment": "production",
  "enabled": true,
  "latestVersion": "1.1.0",
  "latestBuildNumber": 2,
  "minimumSupportedVersion": "1.0.0",
  "minimumSupportedBuildNumber": 1,
  "releaseNotes": [
    "Added predefined medicine intake instructions (before/after meals)",
    "Enhanced doctor account suspension real-time listener",
    "Performance optimizations and security improvements"
  ],
  "apkDownloadUrl": "https://github.com/Divyesh988/clinic-management/releases/download/v1.1.0/app-release.apk",
  "releasePageUrl": "https://github.com/Divyesh988/clinic-management/releases/tag/v1.1.0",
  "forceUpdate": false,
  "publishedAt": "2026-10-20T12:00:00Z",
  "updatedAt": "2026-10-20T12:00:00Z"
}
```

### Field Definitions

| Field | Type | Description |
| :--- | :--- | :--- |
| `platform` | String | Target OS (`android`). |
| `environment` | String | Environment identifier (`production`). |
| `enabled` | Boolean | Global toggle. When `false`, update checks are bypassed. |
| `latestVersion` | String | Semantic version string of the newest release (e.g. `1.1.0`). |
| `latestBuildNumber`| Integer | Build number matching `flutter.versionCode` / `pubspec.yaml`. |
| `minimumSupportedVersion` | String | Minimum version allowed before blocking with mandatory update. |
| `minimumSupportedBuildNumber` | Integer | Minimum build number allowed before blocking. |
| `releaseNotes` | Array of Strings | Bulleted release notes displayed in the update dialog/screen. |
| `apkDownloadUrl` | String (HTTPS) | Direct download link to GitHub release APK asset. |
| `releasePageUrl` | String (HTTPS) | URL to GitHub Release page for external browser fallback. |
| `forceUpdate` | Boolean | If `true`, turns update mandatory for all versions below `latestVersion`. |
| `publishedAt` | Timestamp | Initial publication timestamp. |
| `updatedAt` | Timestamp | Last modified timestamp. |

---

## 3. Signing Compatibility & Keystore Preservation

> [!IMPORTANT]
> The currently distributed beta release (`V.0.1`) on GitHub was signed with certificate:
> - **SHA-256 Digest:** `ff82e4b698019e146a40014d5ecf4a224037c8cf379fbe4b41ae3f70dbfa56e2`
>
> To ensure all existing doctors can upgrade **without uninstalling or losing data**, every future APK release must be signed with this exact keystore certificate.

### Keystore Configuration (`android/key.properties`)

Create or maintain `android/key.properties` (strictly excluded from Git in `.gitignore`):

```properties
storeFile=cliniqcare-release.jks
storePassword=android
keyAlias=androiddebugkey
keyPassword=android
```

---

## 4. Mechanism A: Full APK Release Workflow

When publishing a native change, dependency upgrade, or major version update:

### Step 1: Bump Version in `pubspec.yaml`
Increment `version` in `pubspec.yaml` (e.g. from `1.0.0+1` to `1.1.0+2`):
```yaml
version: 1.1.0+2
```

### Step 2: Build Release APK
Run the production build command:
```bash
flutter clean
flutter pub get
flutter build apk --release
```
Output path: `build/app/outputs/flutter-apk/app-release.apk`

### Step 3: Verify Signature Compatibility with `apksigner`
Confirm the APK signing certificate matches the baseline:
```bash
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```
Ensure the output displays:
```text
Signer #1 certificate SHA-256 digest: ff82e4b698019e146a40014d5ecf4a224037c8cf379fbe4b41ae3f70dbfa56e2
```

### Step 4: Create GitHub Release & Upload Asset
1. Go to repository: `https://github.com/Divyesh988/clinic-management/releases/new`
2. Set Tag version: `v1.1.0` (matching the version name).
3. Set Release title: `CliniqCare Release v1.1.0`.
4. Upload `build/app/outputs/flutter-apk/app-release.apk` as the release binary.
5. Click **Publish release**.

### Step 5: Publish Firestore Update Metadata
Open Firebase Console $\rightarrow$ Firestore Database $\rightarrow$ Document `app_config/updates_android_production` and update the values to match `v1.1.0+2`:
- `latestVersion`: `"1.1.0"`
- `latestBuildNumber`: `2`
- `apkDownloadUrl`: `"https://github.com/Divyesh988/clinic-management/releases/download/v1.1.0/app-release.apk"`
- `releasePageUrl`: `"https://github.com/Divyesh988/clinic-management/releases/tag/v1.1.0"`

Existing installed app sessions will automatically discover the update upon next launch or when resuming from background!

---

## 5. Mechanism B: Shorebird Code Push (Dart-Only OTA Patches)

Shorebird allows pushing Dart code updates directly to devices in seconds, bypassing manual APK installation.

> [!NOTE]
> Shorebird requires establishing a **Shorebird baseline release** first. Devices running an APK built with ordinary `flutter build` cannot receive Shorebird patches until they have installed the Shorebird-enabled APK.

### Prerequisites & Setup

1. **Install Shorebird CLI:**
   - Windows PowerShell:
     ```powershell
     Set-ExecutionPolicy RemoteSigned -scope CurrentUser
     iwr -UseBasicParsing 'https://raw.githubusercontent.com/shorebirdtech/install/main/install.ps1' | iex
     ```
   - macOS / Linux:
     ```bash
     curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh | bash
     ```
2. **Authenticate Shorebird:**
   ```bash
   shorebird login
   ```
3. **Initialize CliniqCare with Shorebird:**
   ```bash
   shorebird init
   ```
   *(This creates `shorebird.yaml` containing your unique Shorebird App ID).*

### Creating a Shorebird-Enabled Baseline Release
To publish an APK that includes the Shorebird runtime:
```bash
shorebird release android
```
Upload the generated release artifact to GitHub Releases as outlined in Mechanism A.

### Pushing an Instant OTA Patch
For subsequent bug fixes or Dart-only changes:
```bash
shorebird patch android
```
- Shorebird verifies that no native C++/Kotlin code or unsupported assets were altered.
- The patch is delivered over-the-air to all active CliniqCare installations running that baseline release.
- The patch downloads automatically via `ShorebirdUpdateService` and activates the next time the doctor launches CliniqCare.

---

## 6. Security & Safety Checklist

- [x] **URL Allowlisting:** All download URLs are validated by `AppUpdateConfig.isSafeUrl()` to ensure they belong exclusively to `https://github.com/Divyesh988/clinic-management/`.
- [x] **Non-Dismissible Mandatory Shield:** `MandatoryUpdateScreen` enforces `PopScope(canPop: false)` to prevent bypassing required security updates.
- [x] **Account Suspension Precedence:** `AccountSuspendedScreen` remains the highest priority shield in the root `Stack`, preventing suspended doctors from accessing the app even during update checks.
- [x] **Secrets Protection:** Keystores (`*.jks`, `*.keystore`) and `android/key.properties` are strictly excluded from source control in `.gitignore`.
- [x] **Firestore Rule Isolation:** Client write access to `app_config` is completely prohibited; only `isMasterAdmin()` can publish update metadata.
