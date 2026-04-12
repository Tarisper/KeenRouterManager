# KeenRouterManager

Native macOS app for managing Keenetic and Netcraze router client profiles.

## Features

- Connects to a router using:
  - KeenDNS (`http` / `https`)
  - local DNS name (`http` / `https`)
  - IP address (including custom port)
- Stores router profiles locally in JSON.
- Stores router passwords in the macOS Keychain.
- Stores UI settings locally in JSON.
- Displays router client list.
- Client sorting: online devices first, then by name.
- Assigns access policies to clients.
- One-click internet blocking for a selected client.
- `My Devices` filter: shows only clients whose MAC addresses match local MAC addresses on this Mac.
- Settings window with interface language selection.
- Localized interface strings loaded from JSON (`Russian` / `English`).
- Fixed desktop layout optimized for the current macOS window size used by the app.

## Tech Stack

- Swift
- SwiftUI (`NavigationSplitView`)
- URLSession + Keenetic JSON API
- AppKit bridge for main menu control and fixed window sizing
- JSON-based runtime localization
- Security framework (`Keychain Services`) for password storage

## Requirements

- Xcode (full installation, not Command Line Tools only)
- macOS 15.6 or newer (current app target deployment version)

## Build and Run

1. Open `KeenRouterManager.xcodeproj` in Xcode.
2. Select the `KeenRouterManager` scheme.
3. Press `Run`.

## Project Structure

- `KeenRouterManager/KeenRouterManagerApp.swift` - app entry point, fixed window sizing, and main menu wiring.
- `KeenRouterManager/ContentView.swift` - main UI.
- `KeenRouterManager/MainViewModel.swift` - business logic and UI state.
- `KeenRouterManager/KeeneticAPIClient.swift` - Keenetic HTTP API client.
- `KeenRouterManager/Models.swift` - domain models.
- `KeenRouterManager/RouterEditorView.swift` - router profile create/edit form.
- `KeenRouterManager/SettingsView.swift` - settings window UI.
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
- `settings.json` - UI settings (for example, `My Devices` filter state, selected interface language, and router list visibility)

Router passwords are stored in the system Keychain.

## Notes and Limitations

- Some routers/firmware versions do not accept HTTPS over IP (TLS/SNI limitation), so the app uses scheme/port fallback.
- macOS network diagnostics may print verbose log lines (`boringssl`, `nw_endpoint_flow_*`) during failed fallback attempts.
