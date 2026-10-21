# Offline 2FA

**Offline 2FA** is a fully offline, encrypted two-factor authenticator (TOTP/HOTP) application written in Flutter. All 2FA accounts and secrets are stored in a single encrypted vault file (`.2favault`), unlocked via a master password using Argon2id key derivation and authenticated AES-256-GCM encryption.

There are **zero network permissions**, zero cloud dependencies, no analytics, and no third-party trackers. Think of it as KeePassDX for your 2FA codes, or Authy without the cloud.

---

## Features

- **100% Offline & Private:** Zero network access. No `INTERNET` permission in Android's main manifest, no network packages, no analytics, no telemetry, and no crash reporting.
- **Strong Authenticated Encryption (AEAD):** AES-256-GCM authenticated encryption with Argon2id password hashing. Tampered files or wrong passwords fail cleanly with an authenticated AEAD validation error.
- **Standard OTP Support:**
  - **RFC 6238 TOTP:** Time-based one-time passwords with configurable periods (default 30 s), hash algorithms (SHA1, SHA256, SHA512), and digit counts (6, 7, 8). Real-time visual countdown timer ring with last-5-second warning and next code preview.
  - **RFC 4226 HOTP:** Counter-based one-time passwords with manual code generation and counter increment.
- **Multiple Import & Entry Methods:**
  - **Mobile (Android / iOS):** Live camera QR code scanner, image file QR import, manual entry, or paste `otpauth://` URI.
  - **Desktop (Linux):** Manual entry (primary) and image file QR import. No camera access is ever requested on desktop.
- **Single Encrypted Vault (`.2favault`):** Atomic disk writes with automatic `.bak` backup file retention.
- **Encrypted Export & Smart Import:**
  - Export your encrypted vault (encrypted with your current master password) to user-chosen storage.
  - Import and merge another `.2favault` file seamlessly using duplicate detection (issuer + account + secret match) and conflict resolution.
- **Per-Entry Plaintext Migration:** View and copy secret keys, raw `otpauth://` URIs, and QR codes behind master password re-authentication (obscured by default with eye toggles).
- **Organization & UX:** Real-time search, groups/tags, drag-and-drop reordering, Material 3 theming (System / Light / Dark), and auto-lock with configurable inactivity timeouts and background locking.
- **Clipboard Security:** Auto-clearing clipboard service with configurable delay (15 s, 30 s, 60 s, or Never).

---

## Security & Threat Model

### Cryptographic Architecture (§5.2, §5.3)

1. **Key Derivation (Argon2id):**
   - Pure Dart Argon2id via `hashlib` executed in a background isolate (`Isolate.run`).
   - Production parameters: Memory $m = 65536\text{ KiB}$ (64 MiB), Iterations $t = 3$, Parallelism $p = 1$, Salt length = 16 bytes.
   - Host benchmark: $\approx 260\text{ ms}$, well below the 2.0–2.5 s unlock threshold while maximizing resistance to offline GPU/ASIC brute-force attacks.
2. **Authenticated Encryption (AES-256-GCM):**
   - Cryptographic primitives via `package:cryptography` (`AesGcm.with256bits()`).
   - 12-byte random cryptographic nonce, 16-byte GCM authentication tag.
   - **Header Authentication (AAD):** The entire 47-byte binary header is passed as Additional Authenticated Data (AAD) into AES-GCM. Any byte-flip in the magic, version, KDF parameters, salt, or ciphertext will immediately fail tag verification.

### Threat Protections (§5.1)

- **Device Storage & Stolen Vaults:** Offline brute-force attacks against stolen `.2favault` files are thwarted by memory-hard Argon2id key derivation.
- **Data Tampering & Corruptions:** Authenticated AEAD prevents ciphertext alteration and bit-flipping.
- **Casual Shoulder Surfing:** Plaintext secrets, URIs, and QR codes are obscured by default, and the app locks automatically when backgrounded or inactive.

### Known Limitations (§5.1, §5.2)

- **Compromised Operating System:** Offline 2FA cannot protect against a compromised host OS, root/jailbreak malware with process memory inspection, or system-level keyloggers.
- **No Password Recovery:** There are no backdoors, recovery keys, PINs, or cloud resets. If you lose your master password, your vault cannot be recovered.
- **Dart String Memory Wiping Caveat:** Sensitive key buffers (`Uint8List`) are securely zeroed out on lock, but Dart garbage-collected `String`s cannot be deterministically cleared from VM memory. This is a known architectural property of managed runtimes.
- **No Third-Party Migration QRs in v1:** Third-party app export QRs (such as `otpauth-migration://` from Google Authenticator) are not supported in v1.

---

## Vault File Format (`.2favault` v1)

A `.2favault` file consists of a 47-byte big-endian binary header, followed by the AES-256-GCM ciphertext, followed by the 16-byte GCM authentication tag.

### Binary Layout (§5.4)

| Offset (bytes) | Length | Field | Value / Description |
|---|---|---|---|
| `0..7` | 8 | Magic | ASCII string `2FAVAULT` (`0x32 0x46 0x41 0x56 0x41 0x55 0x4C 0x54`) |
| `8` | 1 | Format version | `0x01` (uint8) |
| `9` | 1 | KDF algorithm | `0x01` = Argon2id (uint8) |
| `10..13` | 4 | Argon2id memory `m` | Memory cost in KiB (uint32 big-endian, e.g. `65536`) |
| `14..17` | 4 | Argon2id iterations `t` | Time cost / iterations (uint32 big-endian, e.g. `3`) |
| `18` | 1 | Argon2id parallelism `p` | Parallelism (uint8, e.g. `1`) |
| `19..34` | 16 | Salt | Cryptographic random salt (`Random.secure()`) |
| `35..46` | 12 | Nonce / IV | Cryptographic random nonce for AES-256-GCM |
| `47 .. N - 17` | Variable | Ciphertext | Encrypted UTF-8 JSON payload |
| `N - 16 .. N - 1` | 16 | GCM Auth Tag | 16-byte AES-256-GCM authentication tag |

### Decrypted JSON Payload Schema (§5.5)

```json
{
  "version": 1,
  "created_at": "2026-10-21T12:00:00.000Z",
  "modified_at": "2026-10-21T12:00:00.000Z",
  "entries": [
    {
      "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
      "type": "totp",
      "issuer": "GitHub",
      "account": "user@example.com",
      "secret": "JBSWY3DPEHPK3PXP",
      "algorithm": "sha1",
      "digits": 6,
      "period": 30,
      "counter": 0,
      "group_ids": ["b1a77492-4f8e-4a6c-9411-9ff546f254b1"],
      "note": "Personal GitHub account",
      "sort_order": 0,
      "created_at": "2026-10-21T12:00:00.000Z",
      "updated_at": "2026-10-21T12:00:00.000Z"
    }
  ],
  "groups": [
    {
      "id": "b1a77492-4f8e-4a6c-9411-9ff546f254b1",
      "name": "Work",
      "sort_order": 0
    }
  ]
}
```

---

## Building and Testing

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, 3.13.5+ / Dart 3.13.5+)
- **Linux Desktop Build Dependencies:**
  ```bash
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
  ```
- **Android Dependencies:** Android SDK with platform-tools and build-tools (minSdk 23+).

### Development & Verification

```bash
# Clone the repository
git clone https://github.com/deadlyunicorn/2fa.git
cd 2fa

# Fetch dependencies
flutter pub get

# Code formatting check
dart format --set-exit-if-changed .

# Static analysis
flutter analyze

# Full unit and widget test suite
flutter test

# Integration test (headless or desktop)
flutter test integration_test/app_flow_test.dart -d linux
```

### Release Builds

```bash
# Linux desktop release bundle
flutter build linux --release

# Android APK release
flutter build apk --release

# Android App Bundle release (for Google Play / distribution)
flutter build appbundle --release
```

### Verifying No-INTERNET Permission

To verify that the release APK contains **no `INTERNET` permission**:

```bash
# Using aapt
aapt dump permissions build/app/outputs/flutter-apk/app-release.apk

# Using apkanalyzer
apkanalyzer manifest permissions build/app/outputs/flutter-apk/app-release.apk
```
Expected output: only `android.permission.CAMERA` (for QR scanning) is present.

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0-only)**. See the [LICENSE](LICENSE) file for details.
