# Rowlight app icon

`Rowlight.icns` is original Rowlight artwork covered by the repository MIT license. The editable source is `scripts/make-icon.swift`, drawn with AppKit paths and gradients; no downloaded artwork or fonts are required.

Regenerate on macOS from the repository root:

```sh
mkdir -p .build/Rowlight.iconset
swift scripts/make-icon.swift .build/Rowlight.iconset
iconutil -c icns .build/Rowlight.iconset -o assets/Rowlight.icns
```

The icon includes 16, 32, 128, 256, and 512 point representations at 1x and 2x. The build copies it into the app resources before signing and declares it in Info.plist.
