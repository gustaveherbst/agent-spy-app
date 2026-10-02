#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Building Release Binaries..."
cd "${ROOT_DIR}"
swift build -c release

APP_NAME="AgentSpy"
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
RELEASE_BIN_DIR="${ROOT_DIR}/.build/release"

echo "==> Packaging ${APP_NAME}.app..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executables
cp "${RELEASE_BIN_DIR}/AgentTaskMonitor" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${RELEASE_BIN_DIR}/agenttaskd" "${APP_BUNDLE}/Contents/MacOS/agenttaskd"
cp "${RELEASE_BIN_DIR}/agenttask" "${APP_BUNDLE}/Contents/MacOS/agenttask"
cp "${RELEASE_BIN_DIR}/agenttask-mcp" "${APP_BUNDLE}/Contents/MacOS/agenttask-mcp"

chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/agenttaskd"
chmod +x "${APP_BUNDLE}/Contents/MacOS/agenttask"
chmod +x "${APP_BUNDLE}/Contents/MacOS/agenttask-mcp"

# Copy Icon
if [[ -f "${ROOT_DIR}/Resources/AppIcon.icns" ]]; then
    cp "${ROOT_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi
if [[ -f "${ROOT_DIR}/Resources/AgentSpy-1024x1024.png" ]]; then
    cp "${ROOT_DIR}/Resources/AgentSpy-1024x1024.png" "${APP_BUNDLE}/Contents/Resources/AgentSpy-1024x1024.png"
fi

# Create Info.plist
cat << 'EOF' > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIdentifier</key>
    <string>com.agentspy.app</string>
    <key>CFBundleName</key>
    <string>AgentSpy</string>
    <key>CFBundleDisplayName</key>
    <string>AgentSpy</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>AgentSpy</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 AgentSpy. All rights reserved.</string>
</dict>
</plist>
EOF

echo "==> Creating DMG: ${DMG_PATH}..."
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

DMG_TEMP_DIR="$(mktemp -d -t agentspy_dmg_XXXXXX)"
trap 'rm -rf "${DMG_TEMP_DIR}"' EXIT

cp -R "${APP_BUNDLE}" "${DMG_TEMP_DIR}/"
ln -s /Applications "${DMG_TEMP_DIR}/Applications"

# Create disk image
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_TEMP_DIR}" -ov -format UDZO "${DMG_PATH}"

echo "==> DMG successfully created at: ${DMG_PATH}"
echo "==> Done!"
