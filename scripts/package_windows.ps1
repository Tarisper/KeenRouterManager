$ErrorActionPreference = 'Stop'

$ROOT_DIR = Resolve-Path (Join-Path $PSScriptRoot '..')
$BUILD_DIR = Join-Path $ROOT_DIR 'build'
$DIST_DIR = Join-Path $ROOT_DIR 'dist'
$APP_PATH = Join-Path $DIST_DIR 'KeenRouterManager.exe'

Remove-Item -Recurse -Force $APP_PATH -ErrorAction SilentlyContinue
cmake --build $BUILD_DIR --config Release
cmake --install $BUILD_DIR --prefix $DIST_DIR

# Try to use windeployqt if available
$qtPath = & where.exe windeployqt 2>$null
if ($qtPath) {
    windeployqt $APP_PATH
    Write-Host "windeployqt finished: $APP_PATH"
} else {
    Write-Host "windeployqt not found. Application installed to $APP_PATH (or dist/)"
}

Write-Host "Packaged app: $APP_PATH"
