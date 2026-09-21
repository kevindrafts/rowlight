# Rowlight status

Preview **0.2.0 (build 3)**. Formerly Tableview. Native, read-only CSV/TSV viewer for Apple Silicon and macOS 13+.

The app, Swift executable target, menus, accessibility labels, build scripts, and current README use Rowlight. Historical evidence and GitHub preview releases retain their original names. The canonical repository is `kevindrafts/rowlight`.

Local artifact: `dist/Rowlight.app`. It is ad-hoc signed, not Developer ID signed or notarized. `local.rowlight.csv` is a development bundle identifier; choose the permanent identifier with the LLC's signing setup before distributing a signed release.

The native layout includes a file heading, import options popover, bounded content-aware column widths, comfortable/compact density, system or monospaced text, exact-cell selection, pinned row numbers, literal search/copy, and compact/expanded value inspection. The welcome screen and app menus were verified on the desktop after renaming.

Validation: 21/21 core checks, AppKit UI self-checks, release build, bundle metadata/signature checks, and diff whitespace checks pass. Broad real-world file testing, VoiceOver acceptance, and signed-download testing remain. XLSX, editing, sorting/filtering, and multiple-cell copy are not implemented.

See [open-source readiness audit](docs/open-source-audit.md) and [desktop QA](docs/evidence/desktop-check-2026-09-21.md). The source is licensed under MIT. Contributor and security-reporting guidance and a ready-to-enable CI template are included. GitHub Actions is not yet active because the publishing token lacks workflow permission. Historical commits are retained; no history rewrite was performed. Official signed distribution remains pending the LLC signing setup.

## Publication handoff

The repository has been renamed to `kevindrafts/rowlight` and the MIT-licensed source is committed and pushed. It remains **private**. A source-only `v0.2.0-preview.1` release is prepared as a **draft**.

Automatic approval review blocked public visibility until the maintainer explicitly approves disclosure of the retained Git history, legacy preview ZIPs, and historical machine-path metadata. No credentials were detected in that material. Secret scanning/push protection and private vulnerability reporting remain pending publication. GitHub also rejected branch protection while private because the current plan requires GitHub Pro or a public repository; no plan upgrade was performed.

CI remains a template pending a token with workflow permission (or installation through GitHub's web editor).
