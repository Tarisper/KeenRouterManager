#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
APP_PATH="${DIST_DIR}/KeenRouterManager"

rm -rf "${APP_PATH}"
cmake --build "${BUILD_DIR}" --config Release
cmake --install "${BUILD_DIR}" --prefix "${DIST_DIR}"

# Try to use linuxdeployqt if available
if command -v linuxdeployqt &> /dev/null; then
    linuxdeployqt "${APP_PATH}" -appimage
    echo "AppImage created: ${APP_PATH}.AppImage"
else
    echo "linuxdeployqt not found. Application installed to ${APP_PATH} (or dist/)"
fi

echo "Packaged app: ${APP_PATH}"
