# Security

Sensitive assets are **not** committed to this repository.

## What is kept out of Git

- **Keystores** (`.jks`, `.keystore`, `.p12`, `.key`) — used for signing Android/iOS builds. Stored only on secure machines and in CI secrets.
- **Firebase / Google** — `google-services.json` and `firebase_options.dart` contain API keys and app IDs. Use the `.example` files as templates; real files are generated via Firebase Console or `flutterfire configure` and must not be committed.
- **Environment** — `.env`, `local.properties`, and similar files with secrets or machine-specific paths are ignored.

## How to use secrets

- **Local development:** Copy `google-services.json.example` → `android/app/google-services.json` and `firebase_options.dart.example` → `lib/firebase_options.dart`, then fill in values from Firebase Console. Keep the real files only on your machine.
- **CI (e.g. GitHub Actions):** Store keystore files and Firebase config as GitHub Secrets or use a secret manager; write them at build time and never commit them.
- **Release signing:** Use a release keystore (e.g. `thehunter_release.jks`) only on a secure machine or in CI; never add it to the repo.

If you accidentally commit a key or keystore, rotate the key immediately and remove it from Git history (e.g. with `git filter-repo` or BFG).
