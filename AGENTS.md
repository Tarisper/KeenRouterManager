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

## Router SSH Operations

The built-in Keenetic sshd (default port 222) is fragile — operate accordingly:

- **Lockout policy**: 5 failed authentications → 15-minute lockout. Never retry a failing login more than once or twice; stop and fix the cause first.
- **Session-pool exhaustion**: a single wedged CLI session can make sshd accept authentication but refuse every new session (`exec request failed on channel 0`) until the router is rebooted. Never open interactive/pty sessions (`ssh -tt`, ssh without a remote command, pager-style CLI commands like `dir`); always run one-shot non-interactive commands; never kill a foreground ssh client mid-session — let it finish or close cleanly.
- Batch related remote operations into a single ssh connection; keep the number of connections per task minimal.
- Back up any router file in place before editing (`cp file file.bak-YYYYMMDD`).
- A wedged sshd can only be cleared by a router reboot; rebooting via the HTTP API works (authenticated `GET /rci/system/reboot`). There is no way to restart sshd alone.
- **Key-based login does not work on this firmware** (KeeneticOS 5.1.8): once `~/.ssh/authorized_keys` exists in the user's home, sshd accepts authentication but refuses to open ANY session for that user (key and password alike), until the file is removed via another account's shell. Do not attempt to install SSH keys; use password login.

## Security (top priority)

- Security outweighs convenience in every decision. When in doubt, don't do it.
- Avoid storing credentials: never write router passwords, hashes, or keys into files, notes, chat, or the knowledge base. Use the Keychain and in-memory access only; don't keep copies in `/tmp` or scripts.
- Never open or leave a remotely reachable full-access hole (extra services, port forwards, password-less or key-based root entry points, temporary admin/service accounts) without an explicit, stated reason — and close it the moment the reason expires. Creating a temporary access path and removing it are one task; removal is not optional.

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
- The public [GitHub Wiki](https://github.com/Tarisper/KeenRouterManager/wiki) is user-facing documentation (installation, build, router management, data, CI/CD, troubleshooting). Its local working copy lives in `../KeenRouterManager.wiki` (relative to the repository root). Keep it consistent with the knowledge base and README when external behavior changes.
