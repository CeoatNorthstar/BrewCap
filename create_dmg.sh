#!/bin/bash
set -e

APP_NAME="BrewCap"
APP_PATH="/tmp/BrewCapExport/${APP_NAME}.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1.0")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_TEMP="${APP_NAME}_temp.dmg"
VOL_NAME="Install ${APP_NAME}"
BG_IMG="/tmp/dmg_background.png"
BG_IMG_2X="/tmp/dmg_background@2x.png"
OUTPUT_PATH="${HOME}/Desktop/${DMG_NAME}"
STAGING="/tmp/BrewCapDMGStaging"

# Window dimensions
WIN_W=540
WIN_H=380
WIN_X=200
WIN_Y=120

echo "=== Creating Custom DMG ==="

# Ensure app exists
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    exit 1
fi

# Flush icon cache so Finder picks up the new icon
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$APP_PATH" 2>/dev/null || true
touch "$APP_PATH"

# Clean up
rm -rf "$STAGING" "$OUTPUT_PATH"
mkdir -p "$STAGING/.background"

# Copy app and create Applications symlink
cp -R "$APP_PATH" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

# Copy background images
cp "$BG_IMG" "$STAGING/.background/background.png"
if [ -f "$BG_IMG_2X" ]; then
    cp "$BG_IMG_2X" "$STAGING/.background/background@2x.png"
fi

# Calculate DMG size (app size + 10MB padding)
APP_SIZE_KB=$(du -sk "$STAGING" | cut -f1)
DMG_SIZE_KB=$((APP_SIZE_KB + 10240))

echo "App size: ${APP_SIZE_KB}KB, DMG size: ${DMG_SIZE_KB}KB"

# Create a read-write DMG
hdiutil create -srcfolder "$STAGING" \
    -volname "$VOL_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${DMG_SIZE_KB}k" \
    "/tmp/${DMG_TEMP}"

echo "Mounting DMG for customization..."
DEVICE=$(hdiutil attach -readwrite -noverify "/tmp/${DMG_TEMP}" | grep -E '^/dev/' | head -1 | awk '{print $1}')
echo "Mounted at device: $DEVICE"

sleep 2

# Customize with AppleScript
echo "Applying window customization..."
osascript <<EOF
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {${WIN_X}, ${WIN_Y}, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H))}
        
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        set background picture of theViewOptions to file ".background:background.png"
        
        -- Center icons vertically, spread horizontally
        set position of item "${APP_NAME}.app" of container window to {150, 190}
        set position of item "Applications" of container window to {390, 190}
        
        close
        open
        
        update without registering applications
        delay 2
    end tell
end tell
EOF

sync

echo "Detaching DMG..."
hdiutil detach "$DEVICE" -force

echo "Converting to compressed DMG..."
hdiutil convert "/tmp/${DMG_TEMP}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$OUTPUT_PATH"

# Clean up
rm -rf "$STAGING" "/tmp/${DMG_TEMP}"

echo ""
echo "=== Done! ==="
echo "DMG created at: $OUTPUT_PATH"
ls -lh "$OUTPUT_PATH"
