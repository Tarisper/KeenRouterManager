# KeenRouterManager — Agent Instructions

## Build

Full Xcode installation is required (Command Line Tools alone do not provide `xcodebuild`).

```bash
xcodebuild build \
  -project KeenRouterManager.xcodeproj \
  -scheme KeenRouterManager \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

There is no test suite; verify changes with a successful build and manual runs of the affected scenarios.

## Architecture

- **Single SwiftUI target** — `KeenRouterManager.xcodeproj`, macOS 15.5+. No server component, no background services.
- **`MainViewModel`** is the central business model; views never talk to the network or SSH directly.
- **Router API:** `KeeneticAPIClient.swift` — URLSession + Keenetic JSON API (`auth`, `rci/show/ip/hotspot/host`, `rci/show/rc/ip/hotspot/host`, `rci/show/rc/ip/policy`, `rci/ip/hotspot/host`, `rci/ip/hotspot/wake`) with scheme/port fallback (some firmware rejects HTTPS over IP due to TLS/SNI).
- **Xkeen:** `XkeenSSHClient.swift` runs `/usr/bin/ssh` via `Process` with a temporary `ssh-askpass` helper; Entware paths (`/opt/bin/sh`, `PATH=/opt/bin:/opt/sbin:...`); default SSH port `222`, xkeen path `/opt/sbin/xkeen`.
- **No arbitrary SSH execution** — only the fixed `XkeenCommand` set and file operations with name validation. Xray config replacement accepts only `01_log.json` … `06_policy.json`.
- **Storage:** `~/Library/Application Support/KeenRouterManager/` — `routers.json` (profiles, no passwords) and `settings.json` (UI settings). Passwords live in the macOS Keychain (`KeychainCredentialsStore`), with one-time migration from legacy `credentials.json`. Legacy `KeenMngr` directory is migrated by `AppStorageLocation`.
- **Localization:** runtime JSON — `InterfaceStrings.json` with `ru`/`en` sections, loaded by `LocalizationManager`. No `.strings` files.
- **Client identity:** `RouterClient.id` is the lowercased MAC; clients are merged from two hotspot endpoints by MAC.

## Conventions

- New UI strings go into `InterfaceStrings.json` in BOTH `ru` and `en` sections; no hardcoded strings in views.
- No comments that restate code. Only explain non-obvious intent.
- Smallest coherent change — no refactoring unrelated code.
- Never store router passwords in local JSON files; use `CredentialsStore` (Keychain).
- Never commit router credentials, MAC addresses, personal IP addresses, or host-specific identifiers.
- The `backups/` directory at the repo root is a local working area for downloaded Xray/Xkeen backups (real router configs). It is not part of the project and must stay out of Git (keep it in `.gitignore`).

## Knowledge Base

- The project knowledge base is stored in the Obsidian vault at `../../Documents/guide/Мои проекты/KeenRouterManager/` (relative to the repository root).
- Start with `00 — KeenRouterManager.md`; the remaining pages cover overview, architecture/code, build/release/operations, data/API/security, architectural decisions, and AI-agent context.
- Keep the knowledge base in sync when a change affects project structure, architecture, external behavior, the Keenetic API surface, Xkeen command set, persistent data, security model, build/release procedures, development rules, or another long-lived design decision.
- Update `05 — Принятые решения.md` when introducing or changing a durable architectural decision, including its rationale and relevant trade-offs.
- Small implementation fixes or refactors that do not change the project's meaning, interfaces, operating model, or established decisions do not require a knowledge-base update.
- Do not copy secrets, credentials, MAC addresses, personal IP addresses, or host-specific identifiers into the knowledge base.
- The public [GitHub Wiki](https://github.com/Tarisper/KeenRouterManager/wiki) is user-facing documentation (installation, build, router management, data, CI/CD, troubleshooting). Keep it consistent with the knowledge base and README when external behavior changes.
