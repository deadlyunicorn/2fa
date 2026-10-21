# Agent Instructions

This repo builds **Offline 2FA**, an offline, encrypted TOTP/HOTP authenticator written in Flutter.

1. **Read [`docs/PLAN.md`](docs/PLAN.md) fully before doing anything.** It is the single source of truth: requirements, architecture, the security design, the file format, and the milestone checklist.
2. Work the milestones **in order** (§9). Tick the checkboxes as you finish tasks, and append to the Progress Log (§13).
3. Record any decision not covered by the plan in the Decision Log (§14).
4. Hard rules:
   - The app has **no network access**: no INTERNET permission, no network packages, no analytics.
   - Never log secrets, passwords, or decrypted data. No `print(` in `lib/`.
   - Do not change the `.2favault` v1 binary layout. Any change needs a format version bump plus backward-compatible reading.
   - No camera code paths on desktop or web.
   - Before each commit, `flutter analyze` must be clean and `flutter test` must pass. Use Conventional Commits.
