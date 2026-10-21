# Offline 2FA

**Offline 2FA** is a fully offline, encrypted two-factor authenticator (TOTP/HOTP) application written in Flutter. All 2FA accounts and secrets are stored in a single encrypted vault file (`.2favault`), protected by a master password derived via Argon2id and encrypted with authenticated AES-256-GCM.

There are **zero network permissions**, zero cloud dependencies, no analytics, and no third-party trackers. Think of it as KeePassDX for your 2FA codes, or Authy without the cloud.

---

## Features

- **100% Offline & Private:** No `INTERNET` permission on Android, no network packages, no analytics, no crash reporting.
- **Strong Authenticated Encryption:** AES-256-GCM authenticated encryption with key derivation via Argon2id. Tampered files or wrong passwords fail cleanly with authenticated AEAD validation.
- **Standard OTP Support:**
  - RFC 6238 TOTP (configurable period: default 30s; algorithms: SHA1, SHA256, SHA512; 6–8 digits).
  - RFC 4226 HOTP (counter-based, explicit increment).
- **Multiple Import & Entry Methods:**
  - Mobile (Android / iOS): Live camera QR code scanner, image file QR import, manual entry, or paste `otpauth://` URI.
  - Desktop (Linux): Manual entry (primary) and image file QR import. No camera access is ever requested on desktop.
- **Single Encrypted Vault (`.2favault`):** Atomic writes with automatic `.bak` backup retention.
- **Encrypted Export & Smart Import:**
  - Export your encrypted vault (encrypted with your current master password) to standard storage.
  - Import and merge another `.2favault` file seamlessly with duplicate detection and conflict resolution.
- **Per-Entry Plaintext Migration:** View and copy secret keys, raw `otpauth://` URIs, and QR codes behind master password re-authentication (obscured by default with eye toggles).
- **Organization & UX:** Search, groups/tags, drag-and-drop reordering, Material 3 theming (System/Light/Dark), and auto-lock with configurable inactivity timeouts and background locking.
- **Clipboard Security:** Auto-clearing clipboard service with configurable delay.

---

## Security & Threat Model

### What Offline 2FA Protects Against (§5.1)
- **Device Storage & Vault Theft:** Offline brute force attacks against stolen vault files are mitigated by memory-hard and compute-heavy Argon2id key derivation ($m = 64\text{ MiB}, t = 3, p = 1$).
- **Data Tampering & Bit-Flipping:** AES-256-GCM authenticated encryption authenticates the entire file header as Additional Authenticated Data (AAD) along with ciphertext and a 16-byte GCM authentication tag. Any tampering immediately halts decryption.
- **Casual Shoulder Surfing:** Plaintext secrets, URIs, and QR codes are obscured by default, and the app locks automatically when backgrounded or inactive.

### Limitations & Out of Scope (§5.1, §5.2)
- **Compromised Operating System:** Offline 2FA cannot protect against a compromised host OS, root/jailbreak malware with process memory inspection, or system-level keyloggers.
- **Dart String Immutability:** Sensitive key bytes (`Uint8List`) in memory are zeroed out on lock, but Dart garbage-collected `String`s cannot be deterministically cleared from VM memory. This is a known limitation of managed runtime languages.
- **No Password Recovery:** There are no backdoors, recovery questions, PINs, or cloud resets. If you forget your master password, your vault cannot be decrypted.

---

## Platforms

- **Phase 1 (Supported):** Android (minSdk 23+), iOS, Linux desktop.
- **Future Platforms:** Web, Windows, macOS.

---

## Building and Running

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, Flutter 3.13.5+ / Dart 3.13.5+)
- **Linux Desktop Build Dependencies:**
  ```bash
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
  ```
- **Android Dependencies:** Android SDK with platform-tools and build-tools.

### Development
```bash
# Clone the repository
git clone https://github.com/deadlyunicorn/2fa.git
cd 2fa

# Fetch dependencies
flutter pub get

# Run static analysis
flutter analyze

# Run unit and widget tests
flutter test

# Run on Linux desktop
flutter run -d linux
```

### Release Builds
```bash
# Linux desktop release bundle
flutter build linux --release

# Android APK release
flutter build apk --release
```

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0-only)**. See the [LICENSE](LICENSE) file for the full license text.
