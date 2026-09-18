# Status

Milestone 1 CSV implementation and bounded UI preview **0.1.1 (build 2)** are delivered as a local build. GUI acceptance remains with the parent; no visual QA is claimed. XLSX, editing, and AI are not implemented.

Implemented: SwiftPM TableCore, AppKit Tableview, TableBench, and standalone TableCoreChecks. Read-only byte snapshot, indexed record offsets, on-demand decoding, bounded LRU cache, cancellable background loading/search, stale-result gates, literal values, CSV edge cases/errors, native grid/inspector/find/options, open panel/drop/Finder routing, and separate windows.

Artifact: `dist/Tableview.app` (Apple Silicon, macOS 13+, ad-hoc signed, CSV/TSV Viewer with Alternate rank). No installation or default-association changes. No dependencies outside the repository, AGENTS.md edits, system changes, external publishing, or subagents.

UI preview: restrained teal branding with native controls and semantic light/dark colors; exact-cell selection with a native focus indicator and accessible selected state; fixed row-number ruler synchronized with the visible grid, separate from data columns. Header changes clear selection and restart displayed numbering at 1. Keyboard moves refresh at most the two affected cell views without reloading rows. Inspector shows selected row/column and the complete literal value.

Verification: **21/21 TableCoreChecks passed**, including failure-first header-selection and gutter/selection regression slices. Debug and release AppKit self-checks passed for cell state, inspector, accessibility selected state, horizontal gutter stability, vertical/header geometry, header toggle, blank/ragged rows, and light/dark drawing. Release app build, bundle metadata/signature checks, benchmark contract, and both fixture hash/cache/RSS checks passed. Evidence and limitations are in [testing](docs/testing.md).

Direct execution of the bundled app with `--ui-self-check` exited 134 without diagnostics, while the matching release executable in `.build` passed. Cause is unconfirmed; system logs are inaccessible in this sandbox. Parent must verify the actual bundle on a graphical desktop. No visual acceptance or VoiceOver interaction acceptance is claimed.

| Fixture | Records including header × columns | Index only | First 50 rows ready, including read/index | Peak process RSS |
|---|---:|---:|---:|---:|
| 10 MB | 100,000 × 10 | 0.0368 s | 0.0472 s | 23.4 MiB |
| 100 MB | 1,000,000 × 10 | 0.1746 s | 0.1873 s | 143.0 MiB |

These are single release runs on generated fixtures, with warm filesystem caches. Preview readiness excludes AppKit layout/painting and waits for full indexing. Peak RSS includes hashing. Both source SHA-256 hashes remained identical. See [raw evidence](docs/evidence/) and [method/RED-GREEN history](docs/testing.md).

Limits: 256 MiB/file, 2 million records, 4,096 columns, 8 MiB/record. Cache: 128 rows / 8 MiB accounted storage. Each window owns its snapshot; no external-change watcher. Single-cell selection/copy. Delimiter detection samples the first logical record up to 64 KiB; ambiguous files need override. UTF-8 only. GUI interaction, accessibility, and visual acceptance remain unverified.

No commit or publishing was attempted for this preview. Existing untracked `BUILD_RESULT.md` is preserved. Parent will verify and publish the next preview.
