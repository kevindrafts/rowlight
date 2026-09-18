# Status

Milestone 1 CSV implementation is delivered as a local build. GUI acceptance remains with the parent; no visual QA is claimed. XLSX, editing, and AI are not implemented.

Implemented: SwiftPM TableCore, AppKit Tableview, TableBench, and standalone TableCoreChecks. Read-only byte snapshot, indexed record offsets, on-demand decoding, bounded LRU cache, cancellable background loading/search, stale-result gates, literal values, CSV edge cases/errors, native grid/inspector/find/options, open panel/drop/Finder routing, and separate windows.

Artifact: `dist/Tableview.app` (Apple Silicon, macOS 13+, ad-hoc signed, CSV/TSV Viewer with Alternate rank). No installation or default-association changes. No dependencies outside the repository, AGENTS.md edits, system changes, external publishing, or subagents.

Verification: 18/18 executable behavior checks passed. Harness proved both deliberate failure (exit 1) and passing assertion (exit 0) before implementation. Debug AppKit compilation, release build, benchmark contract, bundle metadata/signature checks, and actual fixture dimension/hash/memory checks passed. Final rerun after the single source diff review passed all of these checks; raw logs are in `docs/evidence/`.

| Fixture | Records including header × columns | Index only | First 50 rows ready, including read/index | Peak process RSS |
|---|---:|---:|---:|---:|
| 10 MB | 100,000 × 10 | 0.0213 s | 0.0258 s | 22.4 MiB |
| 100 MB | 1,000,000 × 10 | 0.1721 s | 0.1837 s | 143.0 MiB |

These are single release runs on generated fixtures, with warm filesystem caches. Preview readiness excludes AppKit layout/painting and waits for full indexing. Peak RSS includes hashing. Both source SHA-256 hashes remained identical. See [raw evidence](docs/evidence/) and [method/RED-GREEN history](docs/testing.md).

Limits: 256 MiB/file, 2 million records, 4,096 columns, 8 MiB/record. Cache: 128 rows / 8 MiB accounted storage. Each window owns its snapshot; no external-change watcher. Single-cell selection/copy. Delimiter detection samples the first logical record up to 64 KiB; ambiguous files need override. UTF-8 only. GUI interaction, accessibility, and visual acceptance remain unverified.

Local commit was attempted after all final checks passed, but sandbox permissions prohibit writing `.git/index.lock` (`Operation not permitted`). Both staging and commit were blocked; no commit was created. Source, evidence, and the built app remain in the workspace. No permission escalation or system change was attempted.
