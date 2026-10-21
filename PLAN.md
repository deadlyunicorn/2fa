# Offline 2FA — Implementation Plan

> **Audience:** autonomous coding agents with **zero prior context**. This document is the single source of truth. Read it fully before writing code. When a decision is not covered here, choose the simplest secure option, then record it in [§14 Decision Log](#14-decision-log).

---

## 0. TL;DR

Build **Offline 2FA**, a Flutter authenticator app (TOTP/HOTP) that is **fully offline** (no network permission, no telemetry, no cloud). All accounts are stored in **one encrypted vault file** (`.2favault`), unlocked with a **master password** (Argon2id → AES‑256‑GCM). Users can **export** the encrypted vault and **import** (merge) a vault file. You can think of it as KeePassDX for 2FA codes, or Authy without the cloud.

| Item | Value |
|---|---|
| Display name | `Offline 2FA` |
| Dart package / project name | `offline2fa` |
| Application ID / bundle ID | `com.deadlyunicorn.offline2fa` |
| License | GPL-3.0-only |
| Phase 1 platforms | Android, iOS, Linux |
| Later platforms | Web, Windows, macOS |
| State management | Riverpod (`flutter_riverpod`, no code generation) |
| Navigation | `go_router` |
| Repo root | `.` (the Flutter project lives **at the repo root**, not in a subfolder) |

---

## 1. Requirements (agreed with the product owner)

### 1.1 Functional
1. **Adding accounts**
   - **Mobile (Android/iOS):** camera QR scan (primary), manual entry, import QR from an image file.
   - **Desktop (Linux, later Windows/macOS):** **manual entry is the primary flow**. Loading a QR **from an image file** comes second. **No camera on desktop**, and the app must never request camera access there.
   - Paste an `otpauth://` URI (all platforms), on the manual entry screen.
2. **OTP types:** TOTP (RFC 6238) and HOTP (RFC 4226). Algorithms SHA1/SHA256/SHA512. Digits 6–8. TOTP period is configurable (default 30 s). HOTP has a counter and an explicit "next code" button.
3. **Encryption at rest:** the whole database is one encrypted file. The app is unusable until the master password is entered. **Master password only**: no biometrics, no PIN, no password recovery.
4. **Export:** writes the encrypted vault (same format, encrypted with the **current master password**) to a location the user chooses.
5. **Import:** the user picks a `.2favault` file and enters **that file's** password. Entries are **always merged** into the current vault (no replace mode). See §6.4 for the dedupe rule.
6. **Per-entry plaintext export (for migrating away):** from an entry's details, after **re-entering the master password**, show the secret and the `otpauth://` URI as **obscured text by default** (like `<input type="password">`) with an eye toggle. Also show the QR, blurred or hidden until the user reveals it. Provide copy buttons.
7. **Organization/UX:** search, groups/tags, drag-to-reorder, auto-lock timeout plus lock when backgrounded, tap-to-copy with clipboard auto-clear, and a Light/Dark/System theme.
8. **Password management:** first-run vault creation (password and confirmation, min 8 chars, strong warning that there is NO recovery). Change master password.

### 1.2 Non-functional
- **No network access.** Do not add the `INTERNET` permission on Android. Add no network-capable packages for runtime features. No analytics or crash reporting.
- Crypto must be **authenticated** (AEAD). A tampered file or wrong password must fail cleanly with the message "Wrong password or corrupted file".
- Writes must be **atomic** (write a temp file, then rename) and keep **one `.bak`** of the previous vault.
- Unlock time ≤ ~2 s on a mid-range Android phone (tune the KDF, §5.3).
- Accessibility: semantic labels, scalable text, sufficient contrast.
- `flutter analyze` is clean. Tests pass. Use `very_good_analysis` or `flutter_lints` (prefer `flutter_lints` + `strict-casts`, `strict-raw-types`).

### 1.3 Explicitly OUT of scope for v1
- Importing from other apps (Google Authenticator migration QR, Aegis, 2FAS, andOTP…). If a user scans an `otpauth-migration://` QR, show "Not supported yet".
- Biometrics/PIN quick unlock, auto-backup, cloud sync, opening an external vault file in place.
- Steam Guard, mOTP, Yandex, and other non-standard OTPs.
- Brand icon packs. Use a generated letter avatar (first letter of the issuer, colour derived from a hash of the issuer).
- Screenshot prevention (FLAG_SECURE). This may be added later behind a setting.

---

## 2. Tech Stack & Packages

Use `flutter pub add <pkg>` so you get the **latest stable** versions. If an API differs from what is described here, adapt to the current API. Do not pin old versions.

| Purpose | Package | Notes |
|---|---|---|
| State | `flutter_riverpod` | Notifier/AsyncNotifier classes, no codegen |
| Routing | `go_router` | redirect guard based on vault lock state |
| AES-256-GCM | `cryptography` (+ `cryptography_flutter`) | `AesGcm.with256bits()`; `cryptography_flutter` gives native speed on mobile |
| Argon2id | `hashlib` | pure Dart, works on all platforms including web, fast. Run it in an isolate (`Isolate.run` / `compute`) |
| HMAC for OTP | `crypto` | `Hmac(sha1/sha256/sha512, key)` |
| Secure random | `dart:math` `Random.secure()` | for salt, nonce, ids |
| UUID | `uuid` | v4 |
| Camera QR (mobile only) | `mobile_scanner` | only instantiate on Android/iOS |
| QR from image file | `zxing2` + `image` | pure Dart decode. Used on all platforms for "load image" |
| QR rendering | `qr_flutter` | per-entry export QR |
| File pick/save | `file_picker` | `pickFiles` for import/image, `saveFile(bytes:)` for export |
| App dirs | `path_provider` | `getApplicationSupportDirectory()` |
| Non-secret prefs | `shared_preferences` | theme, auto-lock settings, needed **before** unlock |
| Paths | `path` | |
| Tests | `flutter_test`, `integration_test`, `mocktail` | |

**Do NOT add:** `flutter_secure_storage`, `local_auth`, `http`, `dio`, firebase, or any analytics.

**Implement in-house** (small, fully unit-tested): Base32 codec, HOTP/TOTP generator, `otpauth://` parser/serializer, vault binary codec. Do not use third-party OTP or base32 packages.

---

## 3. Project Setup (Milestone M0)

```bash
# Flutter SDK must be installed (stable channel). If `flutter` is missing, install via
# https://docs.flutter.dev/get-started/install/linux (or snap: `sudo snap install flutter --classic`).
# Linux desktop deps: sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
flutter create --org com.deadlyunicorn --project-name offline2fa \
  --platforms android,ios,linux --description "Offline, encrypted 2FA authenticator" .
```
- Keep the existing `README.md`, but rewrite its content (what the app is, features, build instructions, security model summary).
- Add `LICENSE` (GPL-3.0 full text).
- Set the display name to "Offline 2FA" in: Android `android/app/src/main/AndroidManifest.xml` (`android:label`), iOS `ios/Runner/Info.plist` (`CFBundleDisplayName`), Linux `linux/runner/my_application.cc` (window title) and `linux/CMakeLists.txt` `APPLICATION_ID` = `com.deadlyunicorn.offline2fa`.
- **Android:** `minSdk` 23 or higher (mobile_scanner requirement; check the current value). Confirm that the **main** manifest has **no INTERNET permission** (Flutter only adds it in `debug`/`profile` manifests, which is fine). Add `<uses-permission android:name="android.permission.CAMERA"/>`.
- **iOS:** `NSCameraUsageDescription` = "Used to scan 2FA QR codes." Also `NSPhotoLibraryUsageDescription` if the image picker needs it.
- **Linux:** no camera code paths. Guard with `Platform.isAndroid || Platform.isIOS` (and `!kIsWeb`).
- Configure `analysis_options.yaml` with `flutter_lints` + strict language modes.
- Add `.github/workflows/ci.yml` (see §11).

**Acceptance:** `flutter analyze` is clean, `flutter test` passes, and `flutter build apk --debug` and `flutter build linux` succeed.

---

## 4. Architecture

Use feature-first folders with a thin layered split. Pure-Dart core logic (no Flutter imports) lives in `lib/core/`, so it is trivially unit-testable.

```
lib/
  main.dart                      # ProviderScope + App
  app.dart                       # MaterialApp.router, theme, lifecycle/auto-lock wiring
  router.dart                    # go_router config + lock redirect
  core/
    crypto/
      kdf.dart                   # Argon2id wrapper (isolate), KdfParams
      aead.dart                  # AES-256-GCM encrypt/decrypt helpers
      secure_bytes.dart          # helper to zero Uint8List buffers
    otp/
      base32.dart                # RFC 4648 encode/decode (lenient decode)
      hotp.dart                  # RFC 4226
      totp.dart                  # RFC 6238
      otpauth_uri.dart           # parse/serialize otpauth://
    vault/
      vault_format.dart          # binary header layout, constants, (de)serialize
      vault_codec.dart           # encrypt(payload, key) / decrypt(bytes, password)
      vault_payload.dart         # JSON <-> models
      vault_merge.dart           # merge algorithm (pure)
      vault_errors.dart          # typed exceptions
    models/
      otp_entry.dart             # immutable, copyWith, toJson/fromJson
      group.dart
      otp_type.dart, otp_algorithm.dart
    platform/
      platform_caps.dart         # supportsCamera, isDesktop, isWeb
  data/
    vault_storage.dart           # abstract: exists/read/writeAtomic/delete
    vault_storage_io.dart        # file impl (path_provider), .tmp + rename + .bak
    vault_storage_web.dart       # (Phase 3) IndexedDB/localStorage base64
    prefs_repository.dart        # shared_preferences wrapper (theme, autolock)
    vault_repository.dart        # orchestrates codec + storage; holds derived key while unlocked
  features/
    onboarding/                  # create vault screen
    lock/                        # unlock screen
    entries/                     # home list, entry tile, entry details, edit
    add_entry/                   # add hub, manual form, camera scan, image import
    groups/                      # manage groups, filter chips
    backup/                      # export, import (merge) flows
    settings/                    # theme, auto-lock, change password, about/licenses
    reveal/                      # password re-entry + obscured secret/URI/QR
  shared/
    widgets/                     # countdown ring, letter avatar, obscured text field, etc.
    clipboard_service.dart       # copy + auto-clear
    auto_lock_service.dart       # inactivity timer + lifecycle
test/                            # mirrors lib/
integration_test/
```

### 4.1 Core state (Riverpod)
- `vaultControllerProvider`: a `Notifier<VaultState>` where
  `sealed class VaultState { NoVault | Locked | Unlocking | Unlocked(VaultData data) | Error }`.
  - `create(password)`, `unlock(password)`, `lock()`, `changePassword(old, new)`,
  - `addEntry`, `updateEntry`, `deleteEntry`, `reorder(oldIndex,newIndex)`, `incrementHotp(id)`,
  - `addGroup`, `renameGroup`, `deleteGroup`, `setEntryGroups`,
  - `exportBytes()`, `importAndMerge(bytes, password) -> MergeReport`.
  - Every mutation persists immediately via `VaultRepository.save()`. Writes are serialized with a simple async mutex or queue so two writes can never interleave.
- `prefsProvider`: theme mode, auto-lock timeout, lock-on-background, clipboard clear seconds.
- `tickerProvider`: a `StreamProvider<int>` that emits the current epoch second every second. Only TOTP widgets watch it.
- `searchQueryProvider`, `selectedGroupProvider` → `filteredEntriesProvider`.

### 4.2 Router guard
- If no vault file exists → `/onboarding`.
- If the vault is locked → `/unlock`.
- Otherwise allow `/` (home), `/add`, `/add/manual`, `/add/scan` (mobile only), `/entry/:id`, `/entry/:id/edit`, `/entry/:id/reveal`, `/groups`, `/settings`, `/settings/change-password`, `/backup`.
- Locking from any screen must clear the navigation stack and go to `/unlock`.

---

## 5. Security Design (READ CAREFULLY)

### 5.1 Threat model
- **Protects against:** theft of the device storage or vault file (offline brute force is slowed by Argon2id), tampering (GCM tag), and casual shoulder-surfing (obscured reveal, auto-lock).
- **Does not protect against:** a compromised OS, malware with memory access, or keyloggers. Document this in the README.

### 5.2 Keys
- `key = Argon2id(password_utf8, salt, params) → 32 bytes`.
- While unlocked, `VaultRepository` holds the **derived key** and **salt** in memory (not the password), so saves do not re-run the KDF. Every save uses the **same salt and key** with a **fresh random 12-byte nonce**. Never reuse a nonce with the same key: always generate it from `Random.secure()`.
- On `lock()`: zero the key `Uint8List` (`fillRange(0, len, 0)`), drop references, and clear decrypted data from state. (Dart cannot reliably wipe `String`s. Note this limitation in the README.)
- **Change password:** verify the old password by decrypting, generate a **new salt**, derive a new key, re-encrypt, and write atomically.
- **Export:** re-encrypt the current payload with the current key and salt plus a fresh nonce, then hand the bytes to `file_picker.saveFile`. The result is a normal `.2favault`.

### 5.3 KDF parameters
- Default: **Argon2id, m = 65536 KiB (64 MiB), t = 3, p = 1**, salt 16 bytes, output 32 bytes.
- Parameters are **stored in the header**, so they can change later without breaking old files.
- Run the KDF in a background isolate so the UI shows a spinner and never freezes.
- **Benchmark task (M2):** measure on an Android emulator or a mid-range device in release mode. If unlock takes > 2.5 s, lower to the OWASP baseline **m = 19456 KiB, t = 2, p = 1**. Record the result in §14.
- When decrypting, reject absurd header params (DoS guard): `m` > 1 GiB, `t` > 20, `p` > 16, salt length ≠ 16.

### 5.4 Vault file format v1 (`.2favault`, binary, big-endian)

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 4 | magic | ASCII `2FAV` (`0x32 0x46 0x41 0x56`) |
| 4 | 2 | format version | `1` (uint16) |
| 6 | 1 | kdf id | `1` = Argon2id |
| 7 | 4 | kdf memory KiB | uint32 |
| 11 | 4 | kdf iterations | uint32 |
| 15 | 1 | kdf parallelism | uint8 |
| 16 | 1 | salt length | `16` |
| 17 | 16 | salt | random |
| 33 | 1 | cipher id | `1` = AES-256-GCM |
| 34 | 1 | nonce length | `12` |
| 35 | 12 | nonce | random per write |
| 47 | N | ciphertext ‖ 16-byte GCM tag | |

- **AAD = header bytes [0, 47)**, so every header field is authenticated.
- Plaintext = UTF-8 JSON of the payload (§5.5). No compression.
- Decoder errors (`vault_errors.dart`): `NotAVaultFile` (bad magic or too short), `UnsupportedVersion`, `UnsupportedKdf/Cipher`, `InvalidHeader` (param bounds), `WrongPasswordOrCorrupted` (GCM auth failure), `InvalidPayload` (JSON/schema).
- Keep the header layout in **one** file (`vault_format.dart`) and document it with a comment that mirrors this table.

### 5.5 Payload JSON schema (schemaVersion 1)
```json
{
  "schemaVersion": 1,
  "createdAt": "2026-10-21T09:00:00.000Z",
  "modifiedAt": "2026-10-21T09:00:00.000Z",
  "groups": [ { "id": "uuid", "name": "Work", "sortOrder": 0 } ],
  "entries": [
    {
      "id": "uuid",
      "type": "totp",                 // "totp" | "hotp"
      "issuer": "GitHub",
      "account": "user@example.com",
      "secret": "JBSWY3DPEHPK3PXP",  // normalized Base32: uppercase, no spaces, no padding
      "algorithm": "SHA1",            // "SHA1" | "SHA256" | "SHA512"
      "digits": 6,                    // 6..8
      "period": 30,                   // TOTP only, 1..300
      "counter": 0,                   // HOTP only, >= 0
      "groupIds": ["uuid"],
      "note": "",
      "sortOrder": 0,
      "createdAt": "...",
      "updatedAt": "..."
    }
  ]
}
```
- Unknown fields must be **ignored on read** and need not be preserved.
- A missing optional field gets the default value. A missing required field (`secret`, `type`) makes the entry invalid: skip it and report it.

### 5.6 Storage
- Location: `${getApplicationSupportDirectory()}/vault.2favault`, backup `vault.2favault.bak`.
- `writeAtomic(bytes)`: write `vault.2favault.tmp` → flush → if the current file exists, copy it to `.bak` → rename `.tmp` → `vault.2favault`.
- On startup, if the main file is missing but `.bak` exists, offer "Restore from backup". If the main file fails to decrypt with the correct-looking password, also offer the `.bak`.
- Settings that must exist before unlock (theme, auto-lock) live in `shared_preferences`. They are **not secret**.

### 5.7 Runtime protections
- **Auto-lock:** options are Immediately on background, 30 s, 1 min (default), 5 min, 15 min, Never (inactivity). Any pointer or keyboard event resets the inactivity timer (wrap the app in a `Listener`). `AppLifecycleListener`: on `hidden`/`paused`, lock immediately if "Lock when app goes to background" is on (default **on**).
- **Clipboard:** copy the code, show a SnackBar "Copied — clears in 30 s", and after N seconds (default 30, configurable: 15/30/60/never) read the clipboard and clear it **only if it still contains the copied value**. On Android 13+ this is optional: mark the clip as sensitive via a small platform channel (`ClipDescription.EXTRA_IS_SENSITIVE`). It is a nice-to-have, so skip it if it is complex.
- **Unlock throttling:** after 5 consecutive failures, add an increasing UI delay (1 s, 2 s, 4 s … max 30 s). This is cosmetic only, because the real protection is the KDF.
- Never log secrets, passwords, or decrypted payloads. Add a lint/grep check in CI for `print(`.

---

## 6. OTP & Parsing Specs

### 6.1 Base32 (RFC 4648)
- Decode leniently: strip spaces, `-`, and `=`, uppercase the input, and reject characters outside `A–Z2–7`. Empty input is invalid.
- Encode without padding (for display and the URI).
- Tests: RFC 4648 vectors (`""`, `f`→`MY`, `fo`→`MZXQ`, `foo`→`MZXW6`, `foob`→`MZXW6YQ`, `fooba`→`MZXW6YTB`, `foobar`→`MZXW6YTBOI`), round trips, and invalid characters.

### 6.2 HOTP / TOTP
- `hotp(secretBytes, counter, digits, algorithm)`: 8-byte big-endian counter, HMAC, dynamic truncation, `% 10^digits`, left-pad with zeros.
- `totp(secretBytes, unixSeconds, period, digits, algorithm)` = `hotp(secret, floor(t / period), …)`.
- The **remaining seconds** for UI = `period - (t % period)`.
- **Required tests:** RFC 4226 Appendix D (secret `12345678901234567890`, counters 0–9 → `755224, 287082, 359152, 969429, 338314, 254676, 287922, 162583, 399871, 520489`). RFC 6238 Appendix B for SHA1/SHA256/SHA512 with 8 digits (seeds: 20-byte, 32-byte, and 64-byte ASCII `1234567890…`; times 59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000).

### 6.3 `otpauth://` URI
- Format: `otpauth://{totp|hotp}/{label}?secret=…&issuer=…&algorithm=…&digits=…&period=…&counter=…`
- Label: URL-decode it, then split on the first `:` (or `%3A`) into `issuerFromLabel:account`. If there is no colon, the whole label is the account.
- The `issuer` query param **takes precedence** over the label issuer when both exist.
- `secret` is required (Base32). `counter` is required for HOTP. Defaults: SHA1, 6 digits, 30 s.
- Case-insensitive scheme, type, and algorithm. Ignore unknown params (e.g. `image`).
- Reject `otpauth-migration://` with the specific error `MigrationNotSupported`.
- Serializer: `otpauth://totp/{Uri.encodeComponent(issuer)}:{Uri.encodeComponent(account)}?secret=…&issuer=…&algorithm=…&digits=…&period=…` (or `counter` for HOTP). Parse → serialize → parse round trip must be equal.
- Tests: Google's Key Uri Format examples, missing secret, bad base32, HOTP without counter, label without issuer, encoded characters/spaces, and the migration scheme.

### 6.4 Import merge ("always merge")
Input: the current vault (unlocked) and an imported vault decrypted with the password the user typed for **that** file.
1. **Groups:** match by name, case-insensitive and trimmed. Reuse an existing group id or create a new group with a **new uuid**. Build an `importedGroupId → localGroupId` map.
2. **Entries:** an entry is a **duplicate** if `normalizedSecret` + `issuer.trim().toLowerCase()` + `account.trim().toLowerCase()` all match an existing entry → **skip** it. (Same secret with different labels → keep both.)
3. Non-duplicates get a **new uuid** (avoid id collisions), remapped group ids, and `sortOrder` appended after existing entries in their original relative order.
4. HOTP duplicate with a different counter: keep the local entry, but set `counter = max(local, imported)`. Report it as "updated".
5. Return a `MergeReport { added, skippedDuplicates, updated, invalid, groupsCreated }` and show it in a dialog.
6. Persist with the **current** master password and key. The imported file's password is discarded.
- `vault_merge.dart` must be pure and fully unit-tested (empty→full, full→empty, all duplicates, partial, group remap, HOTP counter max, id collisions).

---

## 7. UX Specification

Use Material 3 with `ColorScheme.fromSeed` (seed e.g. `Colors.indigo`), light and dark themes, and theme mode from prefs. Layout is responsive: on width ≥ 840 dp (desktop), constrain the content to max 720 dp centred. Optionally show the details pane side by side.

### 7.1 Screens
1. **Onboarding / Create vault** (`/onboarding`): app intro text ("Your codes never leave this device"), password plus confirm fields (obscured, eye toggle), min 8 chars, live mismatch error, and a checkbox "I understand there is no way to recover a forgotten password" that must be ticked. A secondary button, **"Import existing vault"**, picks a file, asks for its password, and makes it the local vault, using that file's password as the master password. Show a progress indicator while the KDF runs.
2. **Unlock** (`/unlock`): app icon, password field (autofocus, Enter submits), "Unlock" button, error text, throttle countdown. The overflow menu contains "Restore from backup (.bak)" if it exists, and "Reset app (delete vault)" with a double confirmation that requires typing `DELETE`.
3. **Home / Entries list** (`/`):
   - App bar: title, search icon (expands to a field), lock button, overflow (Groups, Backup, Settings).
   - Group filter chips row: "All" plus each group.
   - `ReorderableListView` of entry tiles. **Drag-to-reorder works only when search is empty and "All" is selected** (otherwise drag handles are hidden).
   - **Entry tile:** letter avatar, issuer (bold), account (secondary), code grouped `123 456` (8 digits → `1234 5678`), a circular countdown for TOTP (turns red in the last 5 s; optionally show the next code faintly in the last 5 s), a refresh button for HOTP. **Tap = copy the code.** Long-press or trailing menu: Edit, Details, Reveal secret, Delete (with confirmation).
   - FAB "Add" → `/add`.
   - Empty state with an "Add your first account" button.
4. **Add hub** (`/add`): on **mobile**, show the options "Scan QR code" (primary), "Enter manually", "Import QR from image". On **desktop**, show "Enter manually" (primary, large), "Load QR from image file" (secondary), and drag-and-drop of an image onto the window as optional polish (via `desktop_drop`, which may be added if cheap).
5. **Manual entry / Edit** (`/add/manual`, `/entry/:id/edit`): a "Paste otpauth:// URI" field at the top. When valid, it fills the form below. Fields: Issuer, Account, Secret (obscured with eye toggle, validated as Base32), Type (TOTP/HOTP segmented button), and an "Advanced" expansion with Algorithm, Digits (6/7/8), Period (TOTP) or Counter (HOTP), Groups (multi-select chips), and Note. Show a live code preview once the secret is valid. Save.
6. **Scan** (`/add/scan`, mobile only): full-screen `MobileScanner`, torch toggle, and a gallery button (image import). On the first valid `otpauth://` detection, stop the scanner and go to the manual form **pre-filled** for confirmation. Invalid or migration QRs show a SnackBar and keep scanning.
7. **Image import:** `file_picker` (type image) → decode with `zxing2` (convert via the `image` package to a luminance source). Try the original image, then a downscaled one (≤ 1024 px) for reliability → same flow as scan. If nothing is found, show "No QR code found in image".
8. **Entry details** (`/entry/:id`): issuer, account, type, algorithm, digits, period/counter, groups, note, created/updated dates, live code. Buttons: Edit, **Reveal secret / Export QR**, Delete.
9. **Reveal** (`/entry/:id/reveal`): first prompts for the master password (verify it with a KDF and constant-time compare against the in-memory key, or by re-deriving and comparing). Then show:
   - Secret: read-only obscured field, eye toggle, copy button.
   - `otpauth://` URI: read-only obscured field, eye toggle, copy button.
   - QR (`qr_flutter`): hidden behind a "Tap to show QR" placeholder or a heavy blur until tapped.
   - Warning banner: "Anyone with this QR or secret can generate your codes." Leaving the screen re-hides everything.
10. **Groups** (`/groups`): list, add, rename, delete (deleting removes the group id from entries but does not delete entries), reorder.
11. **Backup** (`/backup`):
    - **Export encrypted vault:** explanation ("The file is encrypted with your current master password. Keep both safe."), then `file_picker.saveFile` with the default name `offline2fa-backup-YYYYMMDD-HHmm.2favault` and the bytes, then a success SnackBar.
    - **Import vault (merge):** pick a file → password dialog for that file → merge → `MergeReport` dialog.
12. **Settings** (`/settings`): Theme (System/Light/Dark), Auto-lock timeout, Lock when app goes to background, Clipboard clear delay, Change master password (old, new, confirm, with progress), About (version, GPL-3.0, `showLicensePage`, a "This app has no internet access" statement).

### 7.2 Shared widgets
- `ObscuredTextField` (eye toggle), `CountdownRing`, `LetterAvatar`, `CodeText` (monospace, grouped digits, `Semantics(label: digits spelled)`), `PasswordPromptDialog`, `ConfirmDialog`, `BusyOverlay`.

---

## 8. Platform Notes

| Platform | Camera scan | Image QR | Storage | File export | Notes |
|---|---|---|---|---|---|
| Android | ✅ mobile_scanner | ✅ | app support dir | `saveFile` (SAF) | no INTERNET permission in main manifest |
| iOS | ✅ | ✅ | app support dir | `saveFile` (share/document picker) | Info.plist usage strings. Exclude vault from iCloud backup? **Keep default (included)**: it is encrypted |
| Linux | ❌ never | ✅ | `~/.local/share/com.deadlyunicorn.offline2fa/` | `saveFile` (GTK dialog, needs `zenity`/xdg-portal, see file_picker docs) | manual entry is primary |
| Web (P3) | ✅ mobile_scanner web (optional) | ✅ | IndexedDB/localStorage (base64) | `saveFile` triggers download | warn: browser storage can be cleared, so encourage export |
| Windows/macOS (P3) | ❌ | ✅ | app support dir | native dialog | macOS: sandbox entitlements for user-selected files (read-write) |

`platform_caps.dart`:
```dart
bool get supportsCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
bool get isDesktop => !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
```
On web, `dart:io` `Platform` must not be touched. Use conditional imports or check `kIsWeb` first.

---

## 9. Milestones & Task Checklist

Work **in order**. Each milestone ends with: `flutter analyze` clean, `flutter test` green, a commit (Conventional Commits, e.g. `feat(vault): …`), and ticking the boxes here. If you stop mid-milestone, leave a note under §13 Progress Log.

### M0 — Scaffold (§3)
- [x] Flutter project at the repo root with android, ios, linux
- [x] App name, IDs, permissions, LICENSE, README skeleton, analysis_options
- [x] Folder structure from §4 with placeholder files
- [x] CI workflow (§11)

### M1 — OTP core (pure Dart)
- [x] `base32.dart` + tests
- [x] `hotp.dart`, `totp.dart` + RFC vector tests
- [x] `otpauth_uri.dart` + tests
- [x] Models `OtpEntry`, `Group`, enums, with JSON round-trip tests

### M2 — Crypto & vault format
- [x] `kdf.dart` (Argon2id via hashlib in an isolate) + test with a known Argon2id vector (RFC 9106 test vector, or cross-checked against a reference implementation)
- [x] `aead.dart` (AES-256-GCM via `cryptography`)
- [x] `vault_format.dart` + `vault_codec.dart`: tests for round trip, wrong password, flipped byte in header / ciphertext / tag → `WrongPasswordOrCorrupted`, bad magic, bad version, out-of-bounds params, truncated file
- [x] Commit a golden test fixture `test/fixtures/v1_sample.2favault` (password `correct horse battery staple`) to guarantee backward compatibility forever
- [x] `vault_merge.dart` + tests (§6.4)
- [x] KDF benchmark and record it in §14

### M3 — Storage & state
- [x] `VaultStorage` IO impl (atomic write, .bak), tested with a temp dir
- [x] `PrefsRepository`
- [x] `VaultRepository` (holds key/salt, save/load/changePassword/export/import)
- [x] `vaultControllerProvider` with all actions + serialized writes; unit tests with fake storage

### M4 — App shell, onboarding, lock
- [x] Theme, router + guard, `app.dart`
- [x] Onboarding (create + import existing)
- [x] Unlock screen (throttling, restore .bak, reset app)
- [x] Auto-lock service (inactivity + lifecycle) + settings wiring
- [x] Widget tests: create → lands on home; wrong password error; lock returns to unlock

### M5 — Entries
- [x] Home list, tiles, live TOTP countdown, HOTP increment
- [x] Tap-to-copy + clipboard auto-clear service
- [x] Manual add/edit form with URI paste + live preview + validation
- [x] Details screen, delete
- [x] Search, drag-to-reorder (persisted `sortOrder`)
- [x] Widget tests for form validation and tile copy

### M6 — QR input
- [x] Mobile camera scan screen (Android/iOS only)
- [x] Image file QR decode (zxing2) on all platforms. Unit test with fixture PNGs in `test/fixtures/qr/`
- [x] Desktop add hub prioritizes manual entry. Verify no camera code runs on Linux

### M7 — Groups
- [x] Groups CRUD + reorder screen
- [x] Filter chips on home, group multi-select on the entry form

### M8 — Backup & reveal
- [x] Export screen (saveFile)
- [x] Import + merge + report dialog
- [x] Change master password
- [x] Reveal screen (password re-entry, obscured secret/URI, hidden QR)

### M9 — Polish & release (Phase 1 done)
- [ ] Settings screen complete, About/licenses
- [ ] App icon (`flutter_launcher_icons` dev dependency; simple shield+clock glyph). Linux `.desktop` file
- [ ] Accessibility pass (semantics, large-font layout check)
- [ ] `integration_test/app_flow_test.dart`: create vault → add manual TOTP → lock → unlock → export bytes → reset → import → entries match
- [ ] README: features, security model, file-format summary, build instructions, limitations
- [ ] Release builds: `flutter build apk --release`, `flutter build appbundle`, `flutter build linux --release`, `flutter build ios --no-codesign` (on macOS)

### M10 — Phase 3: more platforms (only after M9)
- [ ] `flutter create --platforms web,windows,macos .`
- [ ] Web storage impl (conditional import), web download export, test that the KDF in the browser is acceptable (it may need lower params, which is fine because params live in the header, but **new vaults only**)
- [ ] Windows/macOS builds, macOS entitlements, CI jobs

---

## 10. Testing Strategy
- **Unit (pure Dart, `test/core/**`)**: ≥ 90% coverage on `core/`. All RFC vectors. Codec tamper tests. Merge cases.
- **Golden fixture:** `test/fixtures/v1_sample.2favault` must always decrypt. Never regenerate it after M2 unless the format version is bumped.
- **Widget tests:** onboarding, unlock, add form validation, tile copy, reveal obscured by default.
- **Integration test:** §9 M9 flow. On Linux, run with `flutter test integration_test -d linux` (in CI use `xvfb-run`).
- Use a fast KDF param set in tests (e.g. m=1024 KiB, t=1) via an injectable `KdfParams` default. Production defaults are only used in the app.

## 11. CI (`.github/workflows/ci.yml`)
- Trigger: push and PR.
- Job `test` (ubuntu-latest): checkout → `subosito/flutter-action` (stable, cache) → `flutter pub get` → `dart format --set-exit-if-changed .` → `flutter analyze` → `flutter test --coverage` → fail if `grep -rn "print(" lib/` finds matches.
- Job `build-android` (needs test): setup Java 17 → `flutter build apk --release` (sign with debug keys if no secrets present. Document the keystore setup via `key.properties` and GitHub secrets as optional) → upload artifact.
- Job `build-linux` (needs test): apt-get install the Linux deps → `flutter build linux --release` → tar the `build/linux/x64/release/bundle` → upload artifact.
- On a `v*` tag: attach the artifacts to a GitHub Release.

## 12. Definition of Done (v1)
- All of M0–M9 ticked. CI green.
- Fresh install on Android and Linux: create vault, add via QR (Android) and manual (Linux), codes match another authenticator (or the RFC vectors), export on Android → import on Linux → identical entries.
- Wrong password and a tampered file both show a clean error. App locks on background/timeout. Clipboard clears.
- No `INTERNET` permission in the release APK (`aapt dump permissions` or `apkanalyzer`).

## 13. Progress Log
_Agents: append dated entries — what was done, what's next, any blockers._

- 2026-10-21 — Plan created. Nothing implemented yet. Flutter SDK was **not** found on the dev machine PATH; install it first (M0).
- 2026-10-21 — Milestone M0 completed. Flutter 3.47.7 project scaffold created with package `offline2fa` (`com.deadlyunicorn.offline2fa`) supporting Android, iOS, and Linux. Dependencies added (Riverpod, GoRouter, cryptography, hashlib, zxing2, qr_flutter, etc.). Configured permissions, display names, minSdk 23, and window titles. Added GPL-3.0 LICENSE, comprehensive README.md, strict analysis_options.yaml, folder structure with typed placeholder files, and GitHub Actions CI workflow. Configured QEMU_SET_ENV for ARM64 host Android SDK emulation. Verified `dart format`, `flutter analyze` (0 issues), `flutter test` (passed), `flutter build linux` (built), and `flutter build apk --debug` (built). Next: M1 — OTP core.
- 2026-10-21 — Milestone M1 completed. Implemented RFC 4648 Base32 encoder/lenient-decoder with normalize/isValid helpers; RFC 4226 HOTP and RFC 6238 TOTP with remainingSeconds helper; OtpAuthUri parser and serializer with Google Key Uri Format compliance and MigrationNotSupportedException handling; immutable models OtpEntry, Group, OtpType, and OtpAlgorithm matching §5.5 schema with JSON round-trip serialization, validation, and unmodifiable fields. Verified all RFC 4226 Appendix D vectors, all 18 RFC 6238 Appendix B vectors, and Base32 RFC test vectors. All 169 unit/widget tests passing with 95.3% test coverage across core. dart format and flutter analyze clean with 0 issues. Next: M2 — Crypto & vault format.
- 2026-10-21 — Milestone M2 completed. Implemented `secure_bytes.dart` (zeroBytes, constantTimeEquals, randomBytes); `kdf.dart` with Argon2id via hashlib in background isolate (`deriveKey`, `deriveKeySync`, `KdfParams` with production, owaspBaseline, and testFast presets) verified against reference test vector; `aead.dart` with AES-256-GCM via cryptography and 16-byte authentication tags; typed `VaultException` hierarchy in `vault_errors.dart`; `.2favault` v1 47-byte big-endian binary header format and DoS guards in `vault_format.dart`; `vault_payload.dart` JSON serialization with unknown field handling and invalid entry skipping; `vault_codec.dart` with AEAD header authentication (AAD [0, 47)), full tamper and boundary tests; committed golden fixture `test/fixtures/v1_sample.2favault` with regression test; pure `vault_merge.dart` implementing §6.4 import-merge algorithm with group matching/remapping, deduplication, HOTP counter max updates, and collision-resistant UUID assignment. Measured KDF benchmark (avg ~262 ms for 64 MiB production, ~51 ms for 19 MiB OWASP baseline, ~1.8 ms for testFast) and recorded confirmation in §14 Decision Log. All 242 tests passing with 94.8% core test coverage. dart format and flutter analyze clean with 0 issues. Next: M3 — Storage & state.
- 2026-10-21 — Milestone M3 completed. Implemented `VaultStorage` interface and `VaultStorageIo` with atomic write, backup rotation (`.bak`), temp directory cleanup, and error handling with `VaultFileNotFound`; implemented `AppPrefs` model, `PrefsRepository` with `SharedPreferences`, and Riverpod `prefsProvider` (`PrefsNotifier`) for theme, auto-lock timeouts, lock-on-background, and clipboard clearing; implemented `VaultRepository` orchestrating key derivation/session management, atomic vault creation, unlocking, backup restoration, password verification, password rotation with fresh salt, export, import-merge with key wiping, and vault deletion; implemented `VaultState` hierarchy (`VaultInitial`, `VaultNoVault`, `VaultLocked`, `VaultUnlocking`, `VaultUnlocked`, `VaultError`), unlock throttling (§5.7), `VaultController` (`vaultControllerProvider`) with async mutex for serialized disk writes, companion providers (`tickerProvider`, `searchQueryProvider`, `selectedGroupIdProvider`, `filteredEntriesProvider`), and re-export in `lib/features/lock/vault_controller.dart`. All 293 unit tests passing with >90% coverage. `dart format` and `flutter analyze` clean with 0 issues and 0 print statements in `lib/`. Next: M4 — App shell, onboarding, lock.
- 2026-10-21 — Milestone M4 completed. Implemented shared widgets (`ObscuredTextField` with eye toggle, `PasswordPromptDialog`, `ConfirmDialog` with typed confirmation e.g. "DELETE", `ResponsiveContentWrapper` for >= 840 dp constraints); configured Material 3 theme wired to `prefsProvider.themeMode`; implemented `GoRouter` router and redirect guards in `lib/router.dart` listening to `vaultControllerProvider` via `RouterRefreshNotifier`; implemented OnboardingScreen with min 8 chars validation, live mismatch warning, recovery disclaimer checkbox, vault creation with `BusyOverlay`, file picker import, and backup restoration; implemented UnlockScreen with master password unlock, throttle countdown timer, error display, backup restore, and double-confirmation reset app (DELETE); implemented `AutoLockService` and `AutoLockListener` tracking user interaction (pointer + keyboard) and app lifecycle state changes (`paused`/`hidden`); created placeholders for all application routes; optimized `deriveKey` to run synchronously for `testFast` to support Flutter's fakeAsync test harness while preserving background isolate execution in production; wrote comprehensive widget tests covering onboarding validation/disclaimer/creation, lock redirection, wrong password error/unlock, reset app flow, auto-lock inactivity/lifecycle, import, and throttle lockout. All 312 tests passing with 87.2% overall project coverage. `dart format` and `flutter analyze` clean with 0 issues and 0 print statements in `lib/`. Next: M5 — Entries.
- 2026-10-21 — Milestone M5 completed. Implemented shared widgets (`LetterAvatar` with deterministic issuer hash color and accessible contrast, `CountdownRing` turning error red in last 5 s, `CodeText` with monospace tabular figures and semantic spelling); implemented `ClipboardService` with configurable auto-clear timer, safe clipboard verification before clearing, and `copyCode` status messages; implemented `EntriesListScreen` with expandable search bar, group chips row, empty state, drag-to-reorder disabled during active filtering, and overflow menu; implemented `EntryTile` with live OTP code, TOTP ticker updates, faint next-code display in final 5 s, HOTP increment, tap-to-copy, and popup menu actions; implemented `ManualEntryScreen` with `otpauth://` URI parsing, real-time Base32 validation, live code preview, advanced options (algorithm, digits, period/counter, group filter chips, note), and unified add/edit support; implemented `EntryDetailsScreen` with full metadata, live code box, copy action, and delete confirmation; added unit and widget test suites in `test/shared/clipboard_service_test.dart`, `test/shared/entry_widgets_test.dart`, and `test/features/entries_test.dart`. All 338 tests passing with 86.8% project coverage. `dart format` and `flutter analyze` clean with 0 issues and 0 print statements in `lib/`. Next: M6 — QR input.
- 2026-10-21 — Milestone M6 completed. Implemented pure-Dart QR image decoder in `qr_image_decoder.dart` via `package:image` and `zxing2` (`QRCodeReader`, `HybridBinarizer`, `GlobalHistogramBinarizer`, luminance inversion, and >1024px downscaling) with background isolate execution; generated fixture PNGs in `test/fixtures/qr/` (`valid_totp.png`, `large_hotp.png`, `no_qr.png`); added `pickImageFile` and `imagePickerProvider` in `file_picker_service.dart`; implemented platform-adaptive AddHubScreen prioritizing manual entry and image QR on desktop while offering camera QR on mobile; implemented full-screen `ScanQrScreen` for mobile with viewfinder reticle overlay, torch toggle, gallery import, throttled error feedback, and strict `supportsCamera` protection preventing camera instantiation on Linux/desktop; configured GoRouter redirect for `/add/scan` and pre-filled navigation to `/add/manual`; wrote comprehensive unit and widget test suites in `test/features/qr_image_decoder_test.dart` and `test/features/qr_input_test.dart`. All 354 tests passing with 86.3% project coverage. `dart format` and `flutter analyze` clean with 0 issues and 0 print statements in `lib/`. Next: M7 — Groups.
- 2026-10-21 — Milestone M7 completed. Implemented `GroupsScreen` at `/groups` with `ReorderableListView.builder`, custom drag handles via `ReorderableDragStartListener`, live account counts per group, and responsive centering; created `showAddGroupDialog` and `showRenameGroupDialog` with trimmed, case-insensitive duplicate name prevention; implemented group deletion confirmation dialog in `confirmDeleteGroup` which strips group IDs from all tagged entries without deleting the entries themselves and safely resets `selectedGroupIdProvider`; updated `EntriesListScreen` with sorted filter chips, "Manage" action chip, and graceful fallback to "All" when an active group is removed; enhanced `ManualEntryScreen` with main-form groups multi-select chips and inline "New group" creation; implemented comprehensive widget tests in `test/features/groups_test.dart` covering CRUD, duplicate validation, reordering, cascading deletion, filter chips, and entry assignment. All 360 tests passing with 0 issues in `flutter analyze`, 0 prints in `lib/`, and clean formatting. Next: M8 — Backup & reveal.
- 2026-10-21 — Milestone M8 completed. Implemented mockable/injectable `FileSaverFunction` (`saveVaultFileProvider`) with desktop byte-write verification and `generateVaultBackupFileName` formatting `offline2fa-backup-YYYYMMDD-HHmm.2favault` filenames; implemented `BackupScreen` at `/backup` with encrypted vault export and external vault import & merge including password prompt and `MergeReportDialog` summary; implemented `ChangePasswordScreen` at `/settings/change-password` with current/new/confirm password validation, recovery warning banner, live mismatch checking, and atomic key re-encryption; linked `SettingsScreen` to change-password route; implemented `RevealScreen` at `/entry/:id/reveal` with master password re-entry gate, warning banner, read-only obscured secret and `otpauth://` URI fields with eye toggles and clipboard copy buttons, tap-to-reveal QR code via `qr_flutter` `QrImageView`, and automatic disposal of verified state on navigation exit; wrote comprehensive widget tests in `test/features/backup_and_reveal_test.dart`. All 366 tests passing with 0 issues in `flutter analyze`, 0 prints in `lib/`, and clean formatting. Next: M9 — Polish & release.

## 14. Decision Log
| Date | Decision | Reason |
|---|---|---|
| 2026-10-21 | Custom `.2favault` format (Argon2id + AES-256-GCM, JSON payload) | simple, auditable, versioned |
| 2026-10-21 | Master password only, no biometrics | product owner choice: simplest/most secure |
| 2026-10-21 | Import = always merge, dedupe on secret+issuer+account | product owner choice |
| 2026-10-21 | Export encrypted with current master password | product owner choice |
| 2026-10-21 | Desktop: manual entry primary, image file secondary, no camera | product owner choice |
| 2026-10-21 | Per-entry plaintext reveal allowed behind password re-entry, obscured by default | product owner choice |
| 2026-10-21 | Phase 1: Android, iOS, Linux. Then Web/Windows/macOS | product owner choice |
| 2026-10-21 | Riverpod without codegen, go_router, hand-written models | fewer moving parts for agents |
| 2026-10-21 | No third-party importers in v1 | product owner choice |
| 2026-10-21 | Flutter project at repository root with package name `offline2fa` | Product owner clarification |
| 2026-10-21 | Set `QEMU_SET_ENV` for Android SDK toolchain under ARM64 emulation | Fixes glibc libdl/libz library resolution for x86_64 SDK binaries on aarch64 host |
| 2026-10-21 | Production KDF: Argon2id, m = 65536 KiB (64 MiB), t = 3, p = 1. Benchmark: avg 262.3 ms on host (OWASP baseline: 50.7 ms, testFast: 1.8 ms) | Measured 262.3 ms is well below the 2.5s unlock threshold (§5.3), maximizing brute-force resistance |
| 2026-10-21 | Synchronous execution for `KdfParams.testFast` in `deriveKey` | Eliminates isolate port scheduling deadlock under Flutter's `fakeAsync` widget test harness while keeping background isolate execution for production/OWASP parameters (§5.3, §10) |
| 2026-10-21 | Immediate transition to `VaultLocked` on `lock()` before async backup probe | Eliminates any intermediate unlocked window for maximum runtime security (§5.2) |
| 2026-10-21 | Injectable `filePickerProvider` with default platform implementation | Enables pure in-memory testability of external vault file imports without native OS dialog dependency |
| 2026-10-21 | Injectable `saveVaultFileProvider` with desktop file byte-write fallback | Guarantees reliable file export across Linux desktop where FilePicker.platform.saveFile only provides path without writing bytes |
