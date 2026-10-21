# Offline 2FA — Implementation Audit

| | |
|---|---|
| **Audit date** | 2026-10-21 |
| **Audited against** | [`docs/PLAN.md`](PLAN.md) (single source of truth) |
| **Commit audited** | `28b15cb` (HEAD of `main`) plus uncommitted changes (see §6) |
| **Method** | Full read of `lib/core/**` and `lib/data/**`, targeted review of `lib/features/**`, platform configs, and CI. Ran the toolchain, wrote a reproduction test for the most serious finding, and inspected the dependency sources (`cryptography`, `cryptography_flutter`). |

---

## 1. Executive Summary

The implementation is **substantially complete and of good quality**. All milestones M0–M10 are implemented, and the code closely follows the plan's architecture, file layout, crypto design, and binary format. The pure-Dart core (OTP, Base32, `otpauth://`, vault codec, merge) is correct, well tested, and matches the spec.

However, the audit found **two high-severity runtime defects in the lock/state machine**. Neither is caught by the test suite, because tests use a synchronous fast KDF and never trigger real app-lifecycle events:

1. **Auto-lock can be silently undone** by an in-flight write. Reproduced; see F-01.
2. **With the default settings on Android/iOS, auto-lock fires whenever a system file or image picker opens.** This breaks *Import & merge*, *Import QR from image*, and onboarding *Import existing vault*. See F-02.

There are also several medium and low issues, mostly around onboarding routing, web "offline" guarantees, CI rigour, and minor spec deviations.

**Verdict:** Phase 1 is *feature complete* but **not yet at the §12 Definition of Done**. F-01 and F-02 should be fixed before a release.

### Toolchain results (run during the audit)

| Check | Result |
|---|---|
| `flutter analyze` | ✅ No issues |
| `dart format --set-exit-if-changed .` | ✅ 0 files changed |
| `flutter test --coverage` | ✅ 389 tests passed |
| `grep -rn "print(" lib/` | ✅ No matches |
| Coverage `lib/core/` (§10 target ≥ 90%) | ✅ **94.5%** |
| Coverage `lib/data/` / `lib/features/` / `lib/shared/` / total | 87.7% / 84.8% / 85.4% / **87.6%** |
| Lowest-covered files | `file_io_helper_io.dart` 0%, `file_picker_service.dart` 44%, `onboarding_screen.dart` 61%, `qr_image_decoder.dart` 73%, `auto_lock_service.dart` 77% |

---

## 2. Findings

Severity: 🔴 High · 🟠 Medium · 🟡 Low · 🔵 Info

| ID | Sev | Area | Title |
|---|---|---|---|
| F-01 | 🔴 | Security / state | `lock()` races with in-flight mutations, so the vault comes back "unlocked" with no key |
| F-02 | 🔴 | Security / UX (mobile) | Lock-on-background fires when system pickers open, which breaks import flows |
| F-03 | 🟠 | Onboarding / router | `VaultUnlocking` sends onboarding to `/unlock` mid-operation; errors are lost and `setState` can run after dispose |
| F-04 | 🟠 | Web / offline guarantee | Flutter web loads CanvasKit and fonts from Google CDNs by default, so it is not offline |
| F-05 | 🟠 | KDF / §5.3 | Benchmark was run on the dev host, not on an Android device or emulator in release mode |
| F-06 | 🟠 | CI / §11 | The INTERNET-permission check can pass without checking anything, and integration tests are not run in CI |
| F-07 | 🟡 | Runtime protection | Header-bound errors show developer text instead of "Wrong password or corrupted file" |
| F-08 | 🟡 | Key hygiene | Derived keys are not zeroed on failed decrypt; plaintext JSON buffers are never zeroed |
| F-09 | 🟡 | Web performance | Importing a 64 MiB/t=3 vault on web runs Argon2id on the UI thread |
| F-10 | 🟡 | Spec deviation | Auto-lock has no "Immediately on background" option (it is a separate toggle) |
| F-11 | 🟡 | Linux packaging | The `.desktop` file is not installed or bundled, and there is no Linux app icon |
| F-12 | 🟡 | Storage | `restoreBackup()` is a non-atomic copy; there is no directory fsync |
| F-13 | 🟡 | Hygiene | Uncommitted ProGuard/R8 changes; `android/.kotlin/` is not ignored |
| F-14 | 🟡 | Docs | README has no `key.properties` signing setup, no Linux `zenity`/portal note, and no web storage caveat |
| F-15 | 🔵 | Dead code | `AutoLockService` class is unused, and the error-type alias typedefs are unused |
| F-16 | 🔵 | Privacy | `mobile_scanner` on Android pulls in Google ML Kit telemetry (blocked only by removing the permission) |
| F-17 | 🔵 | Config | `minSdk = flutter.minSdkVersion` is not pinned, although the Progress Log says "minSdk 23" |
| F-18 | 🔵 | Repo hygiene | `PLAN.md` exists both at the root and in `docs/` (identical); `coverage/` and `.idea/` are present in the working tree |

### F-01 🔴 `lock()` races with in-flight mutations (auto-lock bypass) — **reproduced**

**Where:** [`vault_controller.dart`](../lib/data/vault_controller.dart): `lock()` and `_mutate()`

`_mutate()` runs inside `_mutex`, awaits `_repository.save(...)` (real disk I/O), and then sets `state = VaultUnlocked(outcome.payload)` without condition. `lock()` does **not** take the mutex. If the app is backgrounded or times out during a write (HOTP increment, reorder, edit, import), this happens:

1. `lock()` zeroes the key, and state becomes `VaultLocked`. The router goes to `/unlock`.
2. The disk write finishes, and `_mutate` sets `VaultUnlocked(...)`. **The decrypted vault is shown again**, while `repository.isUnlocked == false`.

`importAndMerge` has the same pattern. `changePassword` re-installs `_derivedKey = newKey` *after* a concurrent `lock()`, which leaves a live key in memory while the UI shows "locked".

**Reproduction:** `audit_lock_race_test.dart` (reproduced in full in the appendix below) blocks `writeAtomic` on a `Completer`, calls `addEntry`, then `lock()`, then releases the write:
```
Expected: <Instance of 'VaultLocked'>
  Actual: VaultUnlocked(entries: 1)
  state=VaultUnlocked(entries: 1), repo.isUnlocked=false
```
This violates §5.2 ("On lock(): … clear decrypted data from state") and §5.7.

> [!NOTE]
> I also checked whether a zeroed key could be used to *encrypt* the file. `cryptography`'s `SecretKeyData` wraps the caller's list **by reference** (it does not copy it). The only `await` before the key is consumed resolves as a microtask, so no event-loop task can run in between today. This is safe for now but fragile. Defensive fix: pass `Uint8List.fromList(key)` into `SecretKey` and zero the copy afterwards.

**Fix:** add a session generation counter (or make `lock()` cancel pending writes). Bump it in `lock()`. In `_mutate`, `importAndMerge`, and `changePassword`, capture the generation before awaiting, and after the await **discard the state update** (and zero any new key) if the generation has changed or `!_repository.isUnlocked`. Add the reproduction test as a regression test.

### F-02 🔴 System pickers trigger lock-on-background (mobile)

**Where:** [`auto_lock_service.dart`](../lib/shared/auto_lock_service.dart) `didChangeAppLifecycleState`; callers in [`backup_screen.dart`](../lib/features/backup/backup_screen.dart), [`add_entry_screen.dart`](../lib/features/add_entry/add_entry_screen.dart), and [`onboarding_screen.dart`](../lib/features/onboarding/onboarding_screen.dart)

On Android, the SAF document picker, the gallery picker, and `saveFile` start a separate full-screen activity. On iOS they present a system controller. Flutter reports `hidden` then `paused`, and with `lockOnBackground = true` (the **default**) the vault locks. No suppression mechanism exists (no "external activity in progress" flag).

Consequences, deduced from the code; Linux and the tests never trigger lifecycle events:
- **Import & merge:** after the picker returns, the router has already moved to `/unlock`, so `BackupScreen` is unmounted and `if (bytes == null || !mounted) return;` **silently aborts** the import.
- **Import QR from image:** the decoded result is lost behind the unlock screen.
- **Export:** the bytes are computed beforehand, so the file is usually written, but the success SnackBar is lost and the user lands on `/unlock`.
- **Onboarding "Import existing vault":** no vault is unlocked yet, so this is not affected by the lock itself, but it is affected by F-03.

**Fix:** add an `AutoLockSuppressor` (for example a Riverpod counter, `ref.read(autoLockSuppressProvider.notifier).during(() => pickFile())`). `didChangeAppLifecycleState` skips the lock while the counter is > 0, and optionally re-arms the inactivity timer. Wrap every `file_picker` and `saveFile` call in it. Add widget tests that simulate `AppLifecycleState.paused` during a picker call (`tester.binding.handleAppLifecycleStateChanged`). **Verify on a real Android device.**

### F-03 🟠 Onboarding operations get redirected to `/unlock` mid-operation

**Where:** [`router.dart`](../lib/router.dart) redirect; `create()`, `importInitialVault()`, and `restoreBackup()` in `VaultController`

All three set `state = VaultUnlocking()` first. The router maps `VaultUnlocking → /unlock`, so the `OnboardingScreen` is **disposed while its async handler is still running**. With the production KDF (hundreds of ms, running in an isolate), this happens:
- **Import existing vault with the wrong password:** state goes to `VaultNoVault`, and the router creates a *new* onboarding screen. The old handler's `catch` calls `setState(() => _errorMessage = msg)` **before** checking `mounted`, which throws `setState() called after dispose()`. The user gets no error feedback.
- **Create fails:** state becomes `VaultError`, so the user is stuck on `/unlock` with **no vault file**. Unlocking then fails with "Main vault file does not exist", and the only way out is "Reset app".
- **Restore `.bak` from onboarding fails:** state becomes `VaultLocked`, which shows the unlock screen for a vault that does not exist.
- The onboarding `BusyOverlay` described in §7.1 never appears, because the screen is replaced.

The tests do not catch this because `KdfParams.testFast` runs synchronously, so no frame is rendered between the two state changes.

**Fix:** use a separate state, such as `VaultCreating`, or carry an origin flag (`VaultUnlocking(fromOnboarding: true)`) that the router leaves on `/onboarding`. On failure, always return to `VaultNoVault(hasBackup: …)`, never to `VaultError` or `VaultLocked`. Move `setState` after the `mounted` checks. Add a test using a KDF stub that actually yields (for example `Future.delayed`).

### F-04 🟠 The web build is not offline

By default, `flutter build web` loads **CanvasKit/Skwasm from `www.gstatic.com`**, and Material text falls back to **Roboto from `fonts.gstatic.com`**. This conflicts with §1.2 ("No network access") and with the in-app "This app has no internet access" statement on web.

**Fix:** build with `--no-web-resources-cdn` (CI and README), bundle a font, and add a strict CSP in `web/index.html` (`default-src 'self'; connect-src 'self'; …`). Document the web-specific caveats.

### F-05 🟠 KDF benchmark not done as specified

§5.3 / M2 require the benchmark to run "on an Android emulator or a mid-range device **in release mode**". The Decision Log records 262 ms measured "on host" (an ARM64 dev machine, JIT/test VM). Argon2id in pure Dart (`hashlib`) at 64 MiB/t=3 on a mid-range phone may well take longer than 2.5 s. M2 is ticked, but its acceptance criterion is not met.

**Fix:** add a hidden or `--dart-define` benchmark entry point, run it with `flutter run --release` on a real mid-range Android device, and record the result in §14. Switch to `owaspBaseline` for new vaults if it takes more than 2.5 s. Existing vaults keep working because the parameters are stored in the header.

### F-06 🟠 CI gaps relative to §10/§11

- **The INTERNET check can pass without checking anything:** `grep -rn … build/app/intermediates/merged_manifests/` returns exit code 2 when that directory does not exist (current AGP versions use a different path, `merged_manifest/<variant>/…`). Inside an `if`, that counts as "not found", so the check always passes. Use `aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk` (or `apkanalyzer manifest permissions`) and fail on a match, as §12 specifies.
- **The integration test is not run in CI.** §10 requires `xvfb-run flutter test integration_test -d linux`.
- **The ≥ 90% `core/` coverage target is not enforced.** Add an `lcov` threshold check.
- **Triggers:** §11 says "push and PR"; CI is limited to `main`. This is minor.
- **Optional release signing via `key.properties` and secrets** is neither implemented nor documented.

### F-07 🟡 Some header errors bypass the generic message

§1.2 says a tampered file must fail with "Wrong password or corrupted file". If someone changes a KDF parameter so it falls outside the allowed bounds, `InvalidHeader('memoryKiB (…) out of safe bounds …')` is raised, and the unlock and import screens show `e.message` to the user unchanged. The same applies to `UnsupportedVersion`, `NotAVaultFile`, and others, and to `InvalidPayload`. **Fix:** in the UI, map every `VaultException` except a deliberately chosen `UnsupportedVersion` message to the §1.2 string (and keep the detail internal only). Also note that `minMemoryKiB = 1` is below Argon2's minimum of `8·p`, so `hashlib` would throw an `ArgumentError` that is not caught as a `VaultException`. Raise the minimum to `8 * parallelism`.

### F-08 🟡 Key and plaintext hygiene gaps

- `VaultCodec.decryptWithPassword`: if `decryptWithKey` throws (wrong password), the freshly derived `key` is never zeroed.
- `encryptWithKey` and `decryptWithKey`: the UTF-8 plaintext `Uint8List` buffers are never zeroed after use.
- `importAndMerge` zeroes the imported key (good). `verifyPassword` zeroes the temporary key (good).

These are cheap fixes that improve the §5.2 hygiene described in the README.

### F-09 🟡 Web import of production-param vaults freezes the UI

On web, `deriveKey` runs synchronously (there are no isolates). New web vaults use `owaspBaseline`, but importing or unlocking a vault created on native (64 MiB, t=3) blocks the main thread for several seconds, and the browser may show an "unresponsive page" warning. Consider a Web Worker, or at least show a clear warning before deriving.

### F-10 🟡 Auto-lock options differ from §5.7

§5.7 lists *Immediately on background, 30 s, 1 min, 5 min, 15 min, Never*. `AutoLockTimeout` provides 30 s / 1 min / 5 min / 15 min / Never, and "lock on background" is a separate switch. That separate switch arguably makes the result *more* expressive. Record it in the §14 Decision Log, or align the options with the plan.

### F-11 🟡 Linux `.desktop` file and icon are not wired up

`linux/com.deadlyunicorn.offline2fa.desktop` exists but is not referenced by `linux/CMakeLists.txt`, and it is not included in the release tarball. `Icon=com.deadlyunicorn.offline2fa` does not resolve, because no icon is installed and `flutter_launcher_icons` does not generate Linux icons. Also, no window icon is set in `my_application.cc`. **Fix:** install the `.desktop` file and a PNG/SVG icon from CMake, or include them in the bundle tarball, and call `gtk_window_set_icon_from_file`.

### F-12 🟡 Storage robustness

- `writeAtomic` follows §5.6. The `.bak` copy is not atomic: a crash during `target.copy(bak)` can leave a truncated `.bak`, but the main file is still intact, so this is acceptable. There is no `fsync` of the directory after `rename`, so on ext4 a power loss right after the rename can lose it. This is low risk.
- `restoreBackup()` uses `bak.copy(target)`, which overwrites the main file **non-atomically**. Use copy-to-`.tmp` and then rename.
- A stale `vault.2favault.tmp` left by a crash is never cleaned up at startup. It is harmless, because the next write overwrites it.

### F-13 🟡 Uncommitted work in the tree

`git status` shows `android/app/build.gradle.kts` has been modified (it adds `proguardFiles(...)`), and `android/app/proguard-rules.pro` and `android/.kotlin/` are untracked. The ProGuard rules keep `shared_preferences` Pigeon/JNI classes, which suggests R8 broke a release build. This was not recorded in the Progress or Decision Log. **Fix:** verify `flutter build apk --release` and run it on a device, commit with a `fix(android): …` message plus a Decision Log entry, and add `android/.kotlin/` to `.gitignore`.

### F-14 🟡 README gaps

The README does not cover: optional release signing (`key.properties` and GitHub secrets, §11); the Linux runtime requirement for `zenity`/xdg-desktop-portal for file dialogs (§8); the web warning "browser storage can be cleared, export regularly" (§8; it is shown in the app but not in the README); and web build flags (F-04).

### F-15 🔵 Dead code

[`AutoLockService`](../lib/shared/auto_lock_service.dart) (the class) is unused, because `AutoLockListener` reimplements the timer. Several `typedef …Exception` aliases in `vault_errors.dart`, the `Base32` alias, `VaultMerge.merge(local|current)`, and `copyWithAutoClear` appear to exist only for compatibility with no callers. Remove them, or document why they are kept.

### F-16 🔵 ML Kit telemetry on Android

`mobile_scanner` uses Google ML Kit on Android, which bundles Firebase `datatransport` telemetry. The team noticed this and removed `INTERNET` and `ACCESS_NETWORK_STATE` with `tools:node="remove"`, which neutralises it, but the code is still in the APK. That matters for F-Droid and privacy-focused distribution. Consider a zxing-based camera scanner for a fully FOSS build flavour.

### F-17 🔵 `minSdk` not pinned

`minSdk = flutter.minSdkVersion` depends on the SDK version. Pin it explicitly (≥ 23, as §3 requires) so behaviour does not change when Flutter is upgraded. The Progress Log claims it was "configured".

### F-18 🔵 Repo hygiene

There are two identical copies of the plan (`/PLAN.md` and `/docs/PLAN.md`). `AGENTS.md` points to `docs/PLAN.md`, so delete the root copy to avoid drift. Make sure `coverage/` and `.idea/` are git-ignored.

---

## 3. Milestone-by-Milestone Conformance

Legend: ✅ conforms · ⚠️ conforms with findings · ❌ not met

| Milestone | Status | Notes |
|---|---|---|
| **M0** Scaffold | ✅ | Project at repo root. Names and IDs are correct on all platforms. GPL-3.0 LICENSE, strict analysis options, and CI are present. `minSdk` is not pinned (F-17). |
| **M1** OTP core | ✅ | Base32 (lenient, rejects invalid lengths), HOTP and TOTP match RFC 4226/6238 with all vectors tested. The `otpauth://` parser follows §6.3: issuer-param precedence, case-insensitivity, `MigrationNotSupported`, round trip. Models are immutable with JSON round-trip tests. |
| **M2** Crypto & format | ⚠️ | The header layout matches the §5.4 table byte for byte, with AAD = [0,47), DoS bounds, and typed errors. Tamper, truncation, and bounds tests and the golden fixture are present. The merge follows §6.4 exactly. **The benchmark was not run on a device (F-05).** Minor issues: F-07, F-08. |
| **M3** Storage & state | ⚠️ | Atomic write plus `.bak`, prefs, a repository holding key and salt (not the password), and a mutex for writes. **`lock()` is not serialised with writes (F-01).** |
| **M4** Shell / onboarding / lock | ⚠️ | Router guard, throttling (1, 2, 4 … 30 s after 5 failures), `.bak` restore, and DELETE reset are implemented. **Onboarding redirect bug (F-03). Auto-lock vs pickers (F-02).** |
| **M5** Entries | ✅ | Tiles with grouped code, countdown (red in the last 5 s), faint next code, HOTP refresh, tap-to-copy with clipboard clear only if unchanged, search, and reorder only when unfiltered. |
| **M6** QR input | ✅ | Camera only when `supportsCamera`; the desktop hub puts manual entry first; zxing2 decoding with downscale and inversion, using fixture PNGs; "Not supported yet" for migration QRs. |
| **M7** Groups | ✅ | CRUD, reorder, delete removes the group id from entries, filter chips, and multi-select on the entry form. |
| **M8** Backup & reveal | ⚠️ | Export filename format, merge report dialog, change password with a new salt, and reveal gated by re-deriving and constant-time comparing, with obscured fields and a hidden QR. **Import is broken on mobile with default settings (F-02).** |
| **M9** Polish & release | ⚠️ | Settings, About, and licenses are done; the accessibility pass (text scale 2.0) is done; README and integration test are present. **The Linux `.desktop` file and icon are not wired up (F-11). The integration test is not in CI (F-06).** iOS `--no-codesign` build is unverified (it needs macOS). |
| **M10** More platforms | ⚠️ | Conditional imports keep `dart:io` off web; web storage via `shared_preferences`/localStorage; macOS entitlements (Release has no network entitlements). **Web is not offline (F-04).** Web KDF freeze (F-09). |

### §12 Definition of Done

| Criterion | Status |
|---|---|
| M0–M9 ticked, CI green | ⚠️ Ticked, but see F-01/F-02/F-05/F-06 |
| Fresh install on Android + Linux; QR on Android; export Android → import Linux | ❓ **Not evidenced.** No device test is recorded, and F-02 suggests Android import fails |
| Wrong password / tampered file → clean error | ⚠️ Mostly; header-bound tampering shows developer text (F-07) |
| Locks on background/timeout | ⚠️ Yes, but the lock can be undone (F-01) |
| Clipboard clears | ✅ |
| No `INTERNET` in release APK | ✅ Verified manually per the Progress Log; the CI check does not actually verify it (F-06) |

---

## 4. Things Done Well

- **The crypto and format code is careful and faithful to the spec:** a single source of truth for the header layout, a full-header AAD, a fresh `Random.secure()` nonce on every write, a new salt on password change, DoS parameter guards, and a golden fixture that protects backward compatibility.
- **The merge algorithm** matches §6.4 exactly: group-name matching, new UUIDs, preserved relative order, HOTP `max(counter)` counted as "updated", and duplicates within the imported file are also handled.
- **Strong offline posture on Android:** permissions are removed explicitly with `tools:node="remove"`, and there are no network packages.
- **Testability:** injectable storage, file picker, saver, clipboard, and KDF parameters. 389 tests, and core coverage of 94.5%.
- **Disciplined process:** Conventional Commits per milestone, plus a detailed Progress Log and Decision Log.

---

## 5. Proposed Next Steps (prioritised)

### P0 — Must fix before any release
1. **Fix F-01:** session-generation guard in `VaultController` for `_mutate`, `importAndMerge`, and `changePassword`. Promote the appendix reproduction test to `test/data/` as a regression test. Also copy the key inside `AeadCipher`.
2. **Fix F-02:** auto-lock suppression around all `file_picker` and `saveFile` calls, plus widget tests that simulate `paused` during a picker call. **Verify on a physical Android device.**
3. **Fix F-03:** keep onboarding operations on `/onboarding` (a separate state or flag), always fail back to `VaultNoVault`, and guard `setState` with `mounted`. Add tests with a KDF that actually yields.

### P1 — Required to meet the plan's acceptance criteria
4. **F-05:** run the release-mode KDF benchmark on a mid-range Android device and update §14 (and the defaults if it takes more than 2.5 s).
5. **F-06:** replace the INTERNET check with `aapt2 dump permissions` on the APK, add an `xvfb-run` integration-test step, and add a coverage-threshold gate for `lib/core`.
6. **F-13:** validate and commit the ProGuard changes, log the decision, and ignore `android/.kotlin/`.
7. **§12 manual DoD run:** fresh install on Android and Linux, QR scan on Android, export Android → import Linux, and check that codes match the RFC vectors or another authenticator. Record the results in the Progress Log.

### P2 — Hardening and polish
8. **F-07 / F-08:** generic user-facing error mapping, `minMemoryKiB ≥ 8·p`, and zeroing of keys and plaintext on all paths.
9. **F-04 / F-09:** `--no-web-resources-cdn`, a bundled font, a CSP, and a warning or worker for heavy KDF on web.
10. **F-11:** install the Linux `.desktop` file and icon, and set the GTK window icon.
11. **F-12:** atomic `restoreBackup`, clean up stale `.tmp` files at startup, and optionally fsync the directory.
12. **F-10 / F-14 / F-17 / F-18:** Decision Log entry for the auto-lock options, README additions, pinned `minSdk`, and repo cleanup.

### P3 — Optional / future
13. **F-15:** remove dead code.
14. **F-16:** evaluate a FOSS camera-scanner flavour (no ML Kit) for F-Droid.
15. Raise coverage for `onboarding_screen.dart` and `file_picker_service.dart`, which are the paths where F-02 and F-03 live.

---

## Appendix A — F-01 reproduction test

```dart
// AUDIT SCRATCH TEST — demonstrates lock()/mutation race. Delete after review.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/crypto/kdf.dart';
import 'package:offline2fa/core/models/otp_entry.dart';
import 'package:offline2fa/core/vault/vault_errors.dart';
import 'package:offline2fa/data/vault_controller.dart';
import 'package:offline2fa/data/vault_repository.dart';
import 'package:offline2fa/data/vault_storage.dart';

class GatedStorage implements VaultStorage {
  Uint8List? main;
  Uint8List? bak;
  Completer<void>? gate;

  @override
  Future<bool> exists() async => main != null;
  @override
  Future<bool> backupExists() async => bak != null;
  @override
  Future<Uint8List> read() async =>
      main ?? (throw const VaultFileNotFound('none'));
  @override
  Future<Uint8List> readBackup() async =>
      bak ?? (throw const VaultFileNotFound('none'));
  @override
  Future<void> writeAtomic(Uint8List bytes) async {
    if (gate != null) await gate!.future; // simulate slow disk I/O
    if (main != null) bak = main;
    main = Uint8List.fromList(bytes);
  }

  @override
  Future<void> restoreBackup() async => main = bak;
  @override
  Future<void> delete() async => main = bak = null;
}

void main() {
  test('lock() during an in-flight save must leave the vault locked', () async {
    final storage = GatedStorage();
    final repo = VaultRepository(
      storage: storage,
      defaultKdfParams: KdfParams.testFast,
    );
    final container = ProviderContainer(
      overrides: [
        vaultStorageProvider.overrideWithValue(storage),
        vaultRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(vaultControllerProvider.notifier);
    await ctrl.create('password123');

    storage.gate = Completer<void>();
    final entry = OtpEntry.fromJson(<String, dynamic>{
      'id': 'e1',
      'type': 'totp',
      'issuer': 'X',
      'account': 'y',
      'secret': 'JBSWY3DPEHPK3PXP',
    });
    final pending = ctrl.addEntry(entry); // save now blocked on disk I/O
    await Future<void>.delayed(Duration.zero);

    await ctrl.lock(); // e.g. app goes to background
    expect(container.read(vaultControllerProvider), isA<VaultLocked>());

    storage.gate!.complete(); // disk write finishes
    await pending;

    final state = container.read(vaultControllerProvider);
    // BUG: state flips back to VaultUnlocked with decrypted data even though
    // the repository key was wiped.
    expect(
      state,
      isA<VaultLocked>(),
      reason: 'state=$state, repo.isUnlocked=${repo.isUnlocked}',
    );
  });
}
```
