#!/bin/bash
set -e

APP_NAME="BrewCap"
DMG_NAME="${APP_NAME}.dmg"
DMG_TEMP="${APP_NAME}_temp.dmg"
VOL_NAME="${APP_NAME}"
APP_PATH="/tmp/BrewCapExport/${APP_NAME}.app"
BG_IMG="/tmp/dmg_background.png"
OUTPUT_PATH="${HOME}/Desktop/${DMG_NAME}"
STAGING="/tmp/BrewCapDMGStaging"

echo "=== Creating Custom DMG ==="

# Clean up
rm -rf "$STAGING" "$OUTPUT_PATH"
mkdir -p "$STAGING/.background"

# Copy app and create Applications symlink
cp -R "$APP_PATH" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

# Copy background image
cp "$BG_IMG" "$STAGING/.background/background.png"

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

# Use AppleScript to customize the DMG window
echo "Applying window customization..."
osascript <<EOF
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 760, 500}
        
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set background picture of theViewOptions to file ".background:background.png"
        
        -- Position the app icon (left side)
        set position of item "${APP_NAME}.app" of container window to {165, 200}
        
        -- Position the Applications alias (right side)  
        set position of item "Applications" of container window to {495, 200}
        
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
