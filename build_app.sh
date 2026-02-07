#!/bin/bash
set -e

cd "$(dirname "$0")/MathsChat"

echo "Cleaning prior builds..."
swift package clean
rm -rf .build/release .build/arm64-apple-macosx/release
rm -rf MathsChat.app

echo "Building release binary..."
swift build -c release

echo "Creating app bundle..."

APP_NAME="MathsChat"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Clean up old bundle
rm -rf "${APP_DIR}"

# Create directory structure
mkdir -p "${MACOS_DIR}"
mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy binary
cp ".build/release/MathsChat" "${MACOS_DIR}/${APP_NAME}"

# ---------- Embed WebRTC.framework (macOS slice) ----------
# The stasel/WebRTC xcframework has platform slices:
#   macos-x86_64_arm64/  (universal macOS — this is what we need)
#   ios-arm64/
#   ios-x86_64_arm64-simulator/
#   ios-x86_64_arm64-maccatalyst/
#
# SPM also symlinks the correct slice into:
#   .build/arm64-apple-macosx/release/WebRTC.framework
#
# We must copy the macOS slice, NOT the iOS one.

WEBRTC_MACOS_FW=""

# Option 1: SPM's platform-specific build output (most reliable)
if [ -d ".build/arm64-apple-macosx/release/WebRTC.framework" ]; then
    WEBRTC_MACOS_FW=".build/arm64-apple-macosx/release/WebRTC.framework"
fi

# Option 2: xcframework macOS slice
if [ -z "${WEBRTC_MACOS_FW}" ]; then
    CANDIDATE=".build/artifacts/webrtc/WebRTC/WebRTC.xcframework/macos-x86_64_arm64/WebRTC.framework"
    if [ -d "${CANDIDATE}" ]; then
        WEBRTC_MACOS_FW="${CANDIDATE}"
    fi
fi

# Option 3: Search for macos in the path
if [ -z "${WEBRTC_MACOS_FW}" ]; then
    WEBRTC_MACOS_FW=$(find .build -path "*macos*" -name "WebRTC.framework" -not -path "*/Headers/*" -type d 2>/dev/null | head -1)
fi

if [ -z "${WEBRTC_MACOS_FW}" ]; then
    echo "ERROR: Could not find macOS WebRTC.framework"
    echo "Available framework slices:"
    find .build -name "WebRTC.framework" -type d 2>/dev/null
    exit 1
fi

echo "Embedding framework: ${WEBRTC_MACOS_FW}"
cp -RL "${WEBRTC_MACOS_FW}" "${FRAMEWORKS_DIR}/"

# Verify it's a macOS binary
if command -v lipo &>/dev/null; then
    echo "  $(lipo -info "${FRAMEWORKS_DIR}/WebRTC.framework/WebRTC" 2>/dev/null || \
             lipo -info "${FRAMEWORKS_DIR}/WebRTC.framework/Versions/A/WebRTC" 2>/dev/null || \
             echo "could not verify architecture")"
fi

# ---------- Fix rpath ----------
# The executable looks for @rpath/WebRTC.framework/WebRTC.
# Ensure @executable_path/../Frameworks is in the rpath.
install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || true

# macOS versioned frameworks use Versions/A/WebRTC as the real binary,
# but the linker expects WebRTC.framework/WebRTC (a symlink).
# Ensure the top-level symlink exists.
FW_DIR="${FRAMEWORKS_DIR}/WebRTC.framework"
if [ ! -e "${FW_DIR}/WebRTC" ] && [ -e "${FW_DIR}/Versions/A/WebRTC" ]; then
    echo "  Creating top-level symlinks for versioned framework..."
    ln -sf "Versions/Current/WebRTC" "${FW_DIR}/WebRTC"
    if [ ! -e "${FW_DIR}/Versions/Current" ]; then
        ln -sf "A" "${FW_DIR}/Versions/Current"
    fi
    if [ -d "${FW_DIR}/Versions/A/Headers" ] && [ ! -e "${FW_DIR}/Headers" ]; then
        ln -sf "Versions/Current/Headers" "${FW_DIR}/Headers"
    fi
fi

# ---------- Info.plist ----------
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.mathschat.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

chmod +x "${MACOS_DIR}/${APP_NAME}"

echo ""
echo "Done! App bundle: $(pwd)/${APP_DIR}"
echo "  open ${APP_DIR}"
