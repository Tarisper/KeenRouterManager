<p align="center">
  <picture>
    <img src="docs/images/app-icon.png" alt="KeenRouterManager icon" width="128">
  </picture>
</p>

<h1 align="center">KeenRouterManager</h1>

<p align="center">
  Native macOS app for managing Keenetic and Netcraze router clients, profiles, and Xkeen.
</p>

<p align="center">
  <a href="https://github.com/Tarisper/KeenRouterManager/releases"><img src="https://img.shields.io/github/v/release/Tarisper/KeenRouterManager?label=release&color=2ea44f" alt="Latest release"></a>
  <a href="https://github.com/Tarisper/KeenRouterManager/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License GPL-3.0"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015.5%2B-black" alt="Platform macOS 15.5+">
  <img src="https://img.shields.io/badge/built%20with-SwiftUI-orange" alt="Built with SwiftUI">
  <img src="https://img.shields.io/badge/status-active-success" alt="Project status active">
</p>

<p align="center">
  <a href="https://github.com/Tarisper/KeenRouterManager/releases">Download</a>
  ·
  <a href="https://github.com/Tarisper/KeenRouterManager/wiki">Wiki</a>
  ·
  <a href="https://github.com/Tarisper/KeenRouterManager/releases/latest">Latest Release</a>
</p>

![KeenRouterManager interface screenshot](docs/images/ingex.png)

## Features

- Connects to a router using:
  - KeenDNS (`http` / `https`)
  - local DNS name (`http` / `https`)
  - IP address (including custom port)
- Stores router profiles locally in JSON.
- Stores router passwords in the macOS Keychain.
- Stores UI settings locally in JSON.
- Searches router clients by name, IP, MAC, policy, and segment.
- Filters router clients by favorites, online status, blocking state, policy, segment, and `My Devices`.
- Sorts router clients by smart order, name, IP, policy, or segment.
- Displays router clients in a native macOS table with a details sheet.
- Client sorting: online devices first, then by name.
- Favorite clients: mark devices with a star and show only favorites from the filter menu.
- Assigns access policies to clients.
- One-click internet blocking for a selected client.
- `My Devices` filter: shows only clients whose MAC addresses match local MAC addresses on this Mac.
- Network overview sheet with connection summary, client counters, and segment/policy breakdowns.
- Router diagnostics helper for endpoint and authentication checks.
- Configuration import/export in JSON format.
- Settings window with interface language selection and Xkeen SSH defaults.
- Xkeen management over SSH using the selected router profile credentials.
- Live command output for long-running Xkeen operations.
- Xkeen backup listing, download, restore, and cleanup helpers.
- Xray config replacement for known JSON config files.
- Localized interface strings loaded from JSON (`Russian` / `English`).
- Native macOS menu bar, toolbar, sidebar, searchable content, and sheet-based detail patterns.

## Xkeen over SSH

The Xkeen window is available from the main toolbar. It uses the currently selected router profile:

- host is taken from the router address;
- username and password are taken from the selected router profile and Keychain entry;
- SSH port and Xkeen executable path are configured globally in Settings;
- default SSH port is `222`;
- default Xkeen path is `/opt/sbin/xkeen`.

Supported Xkeen actions:

- status, start, stop, and restart;
- update Geo databases (`xkeen -ug`);
- update Xray (`xkeen -ux`) with a version picker based on Xkeen's release list;
- update Xkeen (`xkeen -uk`);
- create and restore Xkeen/config backups;
- list, download, and delete backup items from `/opt/backups`;
- replace selected Xray JSON config files in `/opt/etc/xray/configs/`.

For safety, the app does not expose arbitrary SSH command execution. Xray config replacement accepts only JSON files with these exact names:

- `01_log.json`
- `02_dns.json`
- `03_inbounds.json`
- `04_outbounds.json`
- `05_routing.json`
- `06_policy.json`

Selected backups are downloaded as a local `.tar.gz` archive. Command output is streamed while a command runs and terminal control sequences are stripped before display.

## Tech Stack

- Swift
- SwiftUI (`NavigationSplitView`, `Table`, `searchable`, `sheet`, `Settings`, `Window`)
- URLSession + Keenetic JSON API
- `Process` + system `ssh` for Xkeen management
- AppKit file panels for backup downloads and config replacement
- JSON-based runtime localization
- Security framework (`Keychain Services`) for password storage
- SwiftUI `FileDocument` for configuration transfer

## Download

Prebuilt application bundles are available in GitHub Releases.

1. Open the Releases page of this repository.
2. Download either `KeenRouterManager.dmg` or `KeenRouterManager.app.zip` from the latest release.
3. Open the downloaded file and move `KeenRouterManager.app` to `Applications`.

## Requirements for Building from Source

- Xcode (full installation, not Command Line Tools only)
- macOS 15.5 or newer (current app target deployment version)

## Build and Run

1. Open `KeenRouterManager.xcodeproj` in Xcode.
2. Select the `KeenRouterManager` scheme.
3. Press `Run`.

The project currently requires a full Xcode installation. `xcodebuild` is not available when only Command Line Tools are selected.

## Project Structure

- `KeenRouterManager/KeenRouterManagerApp.swift` - app entry point and scene wiring.
- `KeenRouterManager/ContentView.swift` - main router browser window with sidebar, search, filters, favorites, table, and client details sheet.
- `KeenRouterManager/MainViewModel.swift` - business logic, favorite clients, and UI state.
- `KeenRouterManager/KeeneticAPIClient.swift` - Keenetic HTTP API client.
- `KeenRouterManager/Models.swift` - domain models.
- `KeenRouterManager/XkeenModels.swift` - Xkeen commands, SSH profile, results, backup item, and user-facing errors.
- `KeenRouterManager/XkeenSSHClient.swift` - SSH-backed Xkeen command runner, backup transfer, and config upload logic.
- `KeenRouterManager/XkeenControlView.swift` - Xkeen management window.
- `KeenRouterManager/XkeenCommandPresentation.swift` - toolbar/icon metadata for Xkeen commands.
- `KeenRouterManager/XkeenFilePanels.swift` - AppKit save/open panels for Xkeen file workflows.
- `KeenRouterManager/XrayReleaseParser.swift` - parser for Xkeen's Xray release list output.
- `KeenRouterManager/XrayReleaseSelectionView.swift` - Xray version picker sheet.
- `KeenRouterManager/RouterEditorView.swift` - router profile create/edit form with diagnostics.
- `KeenRouterManager/SettingsView.swift` - settings window UI.
- `KeenRouterManager/DashboardView.swift` - network overview sheet.
- `KeenRouterManager/ConnectionDiagnosticsView.swift` - diagnostics sheet and report UI.
- `KeenRouterManager/RouterConfigurationDocument.swift` - import/export document format.
- `KeenRouterManager/RouterConfigurationArchive.swift` - serialized configuration archive model.
- `KeenRouterManager/RouterCommands.swift` - native macOS menu commands.
- `KeenRouterManager/AppUIState.swift` - shared presentation state for import/export, network overview, and diagnostics.
- `KeenRouterManager/LocalizationManager.swift` - runtime localization loader and language selection state.
- `KeenRouterManager/InterfaceStrings.json` - localized interface strings.
- `KeenRouterManager/RouterProfileStore.swift` - file storage for router profiles.
- `KeenRouterManager/CredentialsStore.swift` - Keychain-backed password storage.
- `KeenRouterManager/AppSettingsStore.swift` - file storage for UI settings.
- `KeenRouterManager/LocalMACAddressProvider.swift` - local MAC address discovery.
- `Info.plist` - app bundle metadata and declared localizations.

## Data Storage

By default, files are stored in `~/Library/Application Support/KeenRouterManager/`:

- `routers.json` - router profiles
- `settings.json` - UI settings (for example, `My Devices` filter state, favorite client MAC addresses, selected interface language, router list visibility, Xkeen SSH port, and Xkeen executable path)

Router passwords are stored in the system Keychain.

Configuration export files intentionally exclude passwords. Exported JSON contains router profiles and app settings only; imported profiles continue using Keychain passwords already available on the current Mac.

Xkeen SSH uses the same Keychain password as the selected router profile; no separate SSH password is stored.

## Notes and Limitations

- Some routers/firmware versions do not accept HTTPS over IP (TLS/SNI limitation), so the app uses scheme/port fallback.
- macOS network diagnostics may print verbose log lines (`boringssl`, `nw_endpoint_flow_*`) during failed fallback attempts.
- Xkeen management requires SSH access to the router and an installed Xkeen environment. The app assumes Entware-style paths such as `/opt/bin/sh` and `/opt/sbin/xkeen`.
- Xray update selection depends on the text output produced by Xkeen. If Xkeen changes its prompt format, the version picker may need to be updated.
