# OmniNFC Pro (Flutter scaffold)

NFC reader / tag writer for Android and iOS with role-based access, signed payloads,
read-back verification, and an offline-first audit log.

## Run

```bash
flutter create . --platforms=android,ios --org com.yourco   # generates android/ and ios/ around lib/
flutter pub get
flutter test
flutter run                                  # DEV_AUTH=true by default (local demo accounts)
flutter run --dart-define=DEV_AUTH=false --dart-define=API_BASE=https://your.api
```

Dev accounts (DEV_AUTH only): `owner@demo.local/owner123`, `manager@demo.local/manager123`,
`operator@demo.local/operator123`.

## Required platform config (after `flutter create`)

**Android** `android/app/src/main/AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.NFC"/>
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<uses-feature android:name="android.hardware.nfc" android:required="true"/>
```
- `minSdkVersion 21` in `android/app/build.gradle`.
- `MainActivity` must extend `FlutterFragmentActivity` (needed by `local_auth`).

**iOS** (real device only, paid developer account)
- Xcode: Signing & Capabilities -> add **Near Field Communication Tag Reading**.
- `Info.plist`:
```xml
<key>NFCReaderUsageDescription</key><string>Read and program NFC tags</string>
<key>NSFaceIDUsageDescription</key><string>Unlock OmniNFC Pro</string>
```
- Entitlements `com.apple.developer.nfc.readersession.formats`: `NDEF`, `TAG`.

## Layout

| Path | Purpose |
|---|---|
| `core/permissions.dart` | Role -> permission matrix (`can(role, permission)`) |
| `core/auth_service.dart` | JWT login, secure token storage, biometrics, `DevAuthApi` / `HttpAuthApi` |
| `core/nfc_service.dart` | Session handling, tag snapshot, write + read-back verify, lock, format |
| `core/ndef_codec.dart` | NDEF parsing (URI, Text, JSON, vCard), payload builder, canonical bytes |
| `core/signer.dart` | HMAC-SHA256 signature bound to tag UID |
| `core/storage.dart` | Hive audit queue (offline + sync) and cached tag profiles |
| `features/*` | Login, role-based dashboard, reader, writer, audit log |

## Role matrix

| | Owner | Technical Manager | Operator |
|---|---|---|---|
| Scan / inspect | yes | yes | yes |
| Write / format / lock | yes | yes | no |
| Audit log | yes | no | no |
| Org signing key | yes | no | no |

## Not implemented yet

- **Mifare Classic / DESFire / password protection:** `nfc_manager` exposes the raw tech
  (`MifareClassic`, `IsoDep`), so key auth, sector writes and NTAG password (PWD_AUTH) belong in
  new methods on `NfcService`. Format and permanent lock (NDEF read-only) are done.
- **Backend:** `HttpAuthApi` defines `POST /auth/login` and `POST /audit/batch`. The server must
  verify the JWT signature and enforce the role matrix. The client gate is UX only.
- **Signing key distribution:** the key is typed in on each device. Production should fetch a
  per-org key from your backend/KMS.
- **GPS in audit entries:** fields exist, no location collection.
- **Web (Web NFC) and Next.js dashboard:** separate deliverables.

## Platform limits to know

- iOS CoreNFC cannot read Mifare Classic and cannot write while running in background tag mode.
- Locking is irreversible. HMAC binding stops copying data to another tag, not cloning a tag
  whose UID is rewritable.
- This scaffold has not been compiled here; run `flutter pub get && flutter analyze` first and
  adjust for minor `nfc_manager` version differences.

## Checking without Android Studio

1. Push this folder to a GitHub repo. The workflow in `.github/workflows/build.yml` runs
   `flutter analyze`, `flutter test` and builds a debug APK.
2. Open the run under the Actions tab and download the `omninfc-pro-debug-apk` artifact.
3. Copy `app-debug.apk` to an NFC-enabled Android phone and install it (allow unknown sources).
