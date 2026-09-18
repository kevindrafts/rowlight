#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scripts/swift-local.sh build -c release --arch arm64
bundle="dist/Tableview.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp .build/arm64-apple-macosx/release/Tableview "$bundle/Contents/MacOS/Tableview"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.tableview.csv</string>
<key>CFBundleName</key><string>Tableview</string>
<key>CFBundleDisplayName</key><string>Tableview</string>
<key>CFBundleExecutable</key><string>Tableview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>CSV Text</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>public.comma-separated-values-text</string><string>public.tab-separated-values-text</string></array>
<key>CFBundleTypeExtensions</key><array><string>csv</string><string>tsv</string></array>
</dict></array>
</dict></plist>
PLIST
printf 'APPL????' > "$bundle/Contents/PkgInfo"
codesign --force --sign - "$bundle"
scripts/check-bundle.sh
printf 'Built %s\n' "$bundle"
