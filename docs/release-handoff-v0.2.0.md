# Rowlight v0.2.0 — release handoff to Relic

## Build contract

- App: **Rowlight**.
- Supported hardware: **Apple Silicon (M-series) Macs only**. No Intel or universal build.
- Minimum macOS: **13.0**.
- Permanent bundle ID: **`com.halyardco.rowlight`**.
- Version: **0.2.0** (`CFBundleShortVersionString`); build **3** (`CFBundleVersion`). Existing consistent metadata is preserved.
- Source: **the exact commit referenced by annotated tag `v0.2.0`** in `kevindrafts/rowlight`. Resolve `v0.2.0^{commit}` and build that commit in a clean checkout, not a newer `main` or a modified working tree.

Run `scripts/build-app.sh` to produce `dist/Rowlight.app`. The script builds arm64 only and applies a **local ad-hoc signature**. It does not perform Developer ID signing, notarization, or packaging. The permanent bundle ID is generated correctly by the repository: **preserve it; do not rewrite it at build time**. Preserve the version/build and minimum macOS metadata as well.

## Relic responsibilities

Using Lucas Olson's approved Apple developer account, Relic handles **Developer ID signing under the verified developer name Lucas Olson**, the required distribution-signing configuration, Apple notarization, stapling, and DMG packaging. No Developer ID credentials or notarization secrets belong in this repository.

Before delivery, verify the final app still has the metadata above and contains only an arm64 executable. Return:

1. The final DMG.
2. The **SHA-256 checksum of that final DMG**, computed after all signing, stapling, and packaging changes.
3. The source commit SHA and resolved tag used for the build.
4. The Apple notarization result and submission identifier/log reference.
5. Staple validation and Gatekeeper assessment results for the delivered distribution and contained app, as applicable, plus the verified Developer ID signing identity.

## Publication gate

The **final downloaded DMG must be install-tested before publication**, including opening the DMG, copying Rowlight into Applications, first launch under normal Gatekeeper settings, and opening a sample CSV/TSV. Prefer a separate supported Mac or clean test environment so the check exercises a downloaded artifact, not only the build-machine copy. Verify the download's SHA-256 against the delivered checksum.

The repository preparation and tag do **not** publish a GitHub release or DMG. No official signed, notarized download is available until the final verified artifact is published. The locally generated ad-hoc app is not that artifact.

## Repository preparation verification

- Core checks: **21/21 passed**; deliberate failure-harness mode returned its expected exit 1.
- Debug and release AppKit UI self-checks passed. The bundled executable's UI self-check passed outside the sandbox after an in-sandbox abort without diagnostics.
- Debug/release builds, benchmark contract, bundle verification, and fresh 10 MB / 100 MB fixture hash/cache/RSS checks passed. Fresh benchmark results were checked in temporary storage; historical evidence logs were not rewritten.
- Inspected generated Info.plist: `com.halyardco.rowlight`, Rowlight, version **0.2.0**, build **3**, minimum macOS **13.0**. `lipo -archs` reports only **arm64**, and the executable's `LC_BUILD_VERSION` also reports minimum macOS **13.0**.
- Code-signature inspection reports **ad-hoc**, with no TeamIdentifier. Developer ID signing, notarization, stapling, final DMG verification/install testing, and artifact publication remain Relic/release-owner work.
