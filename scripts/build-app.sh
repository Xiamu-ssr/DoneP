#!/usr/bin/env bash
# 把 SPM 编译产物组装成 DoneP.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DoneP"
BUNDLE_ID="com.xiamu.donep"
VERSION="${1:-0.1.0}"
BUILD_DIR=".build/release"
OUT="dist"
APP="$OUT/$APP_NAME.app"

echo "==> 编译 (release)"
swift build -c release

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

# 图标 (若有 AppIcon.icns)
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# 收款码 / 其它资源
if [ -f "Resources/donate-wechat.png" ]; then
    cp "Resources/donate-wechat.png" "$APP/Contents/Resources/donate-wechat.png"
fi

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$APP"

echo "==> 完成: $APP"
