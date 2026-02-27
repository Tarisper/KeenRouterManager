#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
APP_PATH="${DIST_DIR}/KeenRouterManager.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

rm -rf "${APP_PATH}"
cmake --build "${BUILD_DIR}" --config Release
cmake --install "${BUILD_DIR}" --prefix "${DIST_DIR}"

MACDEPLOYQT="$(brew --prefix qt)/bin/macdeployqt"
QT_LIB_PATH="$(brew --prefix qt)/lib"
"${MACDEPLOYQT}" "${APP_PATH}" -libpath="${QT_LIB_PATH}"

codesign --remove-signature "${APP_PATH}" 2>/dev/null || true
codesign --force --deep --sign "${SIGN_IDENTITY}" --timestamp=none "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

echo "Packaged app: ${APP_PATH}"
