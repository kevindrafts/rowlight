#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
import os, plistlib, subprocess
root = 'dist/Rowlight.app/Contents'
with open(root + '/Info.plist', 'rb') as f:
    p = plistlib.load(f)
assert p['CFBundleExecutable'] == 'Rowlight'
assert p['CFBundleName'] == 'Rowlight'
assert p['CFBundleDisplayName'] == 'Rowlight'
assert p['CFBundleIdentifier'] == 'local.rowlight.csv'
assert p['CFBundleShortVersionString'] == '0.2.0'
assert p['CFBundleVersion'] == '3'
assert p['CFBundlePackageType'] == 'APPL'
assert p['LSMinimumSystemVersion'] == '13.0'
doc = p['CFBundleDocumentTypes'][0]
assert doc['CFBundleTypeRole'] == 'Viewer'
assert doc['LSHandlerRank'] == 'Alternate'
assert 'public.comma-separated-values-text' in doc['LSItemContentTypes']
exe = root + '/MacOS/Rowlight'
assert os.access(exe, os.X_OK)
assert 'arm64' in subprocess.check_output(['file', exe], text=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', 'dist/Rowlight.app'], check=True)
print('PASS bundle metadata, CSV Viewer registration, arm64 executable, signature')
PY
