<img src="data/icons/hicolor/scalable/apps/KeenRouterManagerIcon.png" align="right" width="64" height="64">

# KeenRouterManager (Qt/C++)

<em>Modern Qt6 client for Keenetic routers, rewritten in C++ to stay fast and responsive across platforms.</em>

## Overview

**KeenRouterManager (Qt/C++)** is the native evolution of the original Python/GTK tool [Keenetic-Manager](https://github.com/Toxblh/Keenetic-Manager): it keeps the same router policy workflow but relies on Qt Widgets, CMake, and the Qt Network stack for a snappier UI and better deployability on macOS, Linux, and Windows. The app stores router profiles as JSON configs, speaks to the existing `rci` endpoints, and exposes automation helpers such as Wake-on-LAN. The icon above is exported from `resources/app.icns` so the documentation matches the shipped bundle.

## Highlights

- **Pages:** Me, VPN, Clients, and Settings mirror the most used workflows from the GTK version.
- **Settings:** add/edit/delete routers, import/export the router list, tune network timeouts/retries, toggle prefer-HTTPS, and switch between English and Russian language packs stored in `resources/language_packs.json`.
- **Networking:** authenticates via `/auth` with the same MD5 + SHA256 challenge-response, retrieves policies, clients, KeenDNS URLs, and router IPs, and applies client policies or Wake-on-LAN commands.
- **Deployment:** builds with Qt6/CMake and bundles via platform-specific scripts so that the `.app` or installers include the necessary frameworks.

## macOS prerequisites

Install Qt, CMake, and Ninja via Homebrew:

```bash
brew install qt cmake ninja
```

## Build

```bash
cd cpp-qt
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

## Install

```bash
cmake --install build --prefix dist
```

The install step installs the application bundle into `dist`, which is also used by the deployment scripts.

## Deployment

- **macOS bundle + Qt frameworks:**

```bash
./scripts/package_macos.sh
```

This script rebuilds the `dist` bundle, copies the frameworks/plug-ins, and re-signs it (`ad-hoc`) so the app launches locally.

- **Linux / Windows:**

```bash
cmake --install build --prefix dist
```

After installation use the platform-specific Qt deployer (`linuxdeployqt`/`windeployqt`) to bundle dependencies.

## Platform tips

- macOS: `./scripts/package_macos.sh`
- Linux: `./scripts/package_linux.sh`
- Windows (PowerShell): `./scripts/package_windows.ps1`
