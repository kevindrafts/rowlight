# Rowlight v0.2.1 — release handoff to Relic

This release adds the Rowlight app icon. Build the exact commit resolved by annotated tag `v0.2.1` in `kevindrafts/rowlight` from a clean checkout. Never move or overwrite `v0.2.0` or reuse its artifact for this release.

- App: Rowlight; permanent bundle ID: `com.halyardco.rowlight`.
- Version: **0.2.1**, build **4**.
- Apple Silicon (arm64) only; minimum macOS **13.0**.
- Run `scripts/build-app.sh`. It embeds `assets/Rowlight.icns` and generates a local **ad-hoc** signature. Preserve the icon, bundle ID, version/build, and minimum OS.

Relic handles Developer ID signing under **Lucas Olson (979L474R9G)**, notarization, stapling, and drag-to-Applications DMG packaging. Credentials stay on the signing device, outside this repository.

Discord trigger, sent by the authorized release owner:

```text
release: rowlight v0.2.1
```

Return the final DMG, its SHA-256 checksum computed after all packaging changes, the resolved source commit, Apple notarization result/submission ID, and signing identity, staple validation, and Gatekeeper assessment results for the final distribution and contained app as applicable. Refuse any previously used version whose resolved commit has changed.

Before publication, install-test the **final downloaded DMG** on a supported Mac: verify its checksum, mount it, copy Rowlight to Applications, launch under normal Gatekeeper settings, verify the icon in Finder and the Dock, and open a sample CSV/TSV. The successful v0.2.0 install test does not replace this check.

Pushing a source tag does not publish a signed download. Publish the exact tested DMG and checksum to the GitHub release only after the install test passes; update the README download link then. No official signed download is available until the artifact is published.
