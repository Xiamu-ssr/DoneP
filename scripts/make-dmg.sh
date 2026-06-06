#!/usr/bin/env bash
# 打包 DoneP.app 成 DMG
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DoneP"
VERSION="${1:-0.1.0}"
APP="dist/$APP_NAME.app"
DMG="dist/$APP_NAME-$VERSION.dmg"

[ -d "$APP" ] || { echo "先跑 build-app.sh"; exit 1; }
rm -f "$DMG"

if command -v create-dmg >/dev/null 2>&1; then
    echo "==> 用 create-dmg 打包"
    create-dmg \
        --volname "$APP_NAME $VERSION" \
        --window-pos 200 120 \
        --window-size 520 320 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 130 150 \
        --app-drop-link 390 150 \
        --no-internet-enable \
        "$DMG" "$APP" 2>/dev/null || {
            echo "create-dmg 报错, 退回 hdiutil"
            hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG"
        }
else
    echo "==> 用 hdiutil 打包"
    hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG"
fi

echo "==> 完成: $DMG"
ls -lh "$DMG"
