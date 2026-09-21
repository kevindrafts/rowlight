# Contributing to Rowlight

Rowlight is a native, read-only Mac viewer for delimited text. We prioritize faithful data display, fast navigation, accessibility, and a quiet interface.

## Issues and proposals

Use GitHub Issues for bugs and feature ideas. Include your macOS version, Rowlight version, reproduction steps, and expected behavior. Attach only a small synthetic CSV that reproduces the problem; do not post real customer data or credentials. Discuss larger changes before implementing them.

## Development

You need a Mac with Swift 6 or newer and the macOS SDK. There are no external Swift package dependencies. Run:

```sh
scripts/swift-local.sh run TableCoreChecks
scripts/swift-local.sh run Rowlight --ui-self-check
scripts/build-app.sh
```

The UI self-check needs a graphical macOS session. The CI template runs the core checks and builds/verifies the app bundle once installed (see docs/ci/README.md). Visually inspect UI changes with representative data, light/dark appearances, keyboard navigation, and different window sizes. Include screenshots and relevant checks in your pull request.

Keep changes focused. Preserve literal file content, cancellation, memory bounds, and read-only behavior. Do not commit build artifacts, private files, credentials, or signing certificates. The CI template scans Git history for secrets once enabled; maintainers also scan release commits locally.

By submitting a contribution, you agree to license it under the project's MIT license. Be respectful and constructive; maintainers may decline changes that do not fit the project's scope.
