#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP="$PWD/build/MacTools.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/AppIcon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/MacTools" "$APP/Contents/MacOS/MacTools"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacTools</string>
<key>CFBundleIdentifier</key><string>com.ryanai.mactools</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Mac 工具箱</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign "${MAC_TOOLS_SIGN_IDENTITY:--}" "$APP"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --strict "$APP"
printf '%s\n' "$APP"
