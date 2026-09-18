# Testing evidence

2026-09-17, Apple Silicon, Apple Swift 6.3.3, Command Line Tools only. No XCTest or Testing module is available. The user explicitly authorized replacing the original `.testTarget`/XCTest choice with a standalone executable. No framework downloads, system changes, or AGENTS.md edits were needed.

## Harness and test-first sequence

The assertion harness was validated before parser implementation:

- `TableCoreChecks --prove-failure`: deliberate throwing assertion, **exit 1**, 0/1 passed.
- `TableCoreChecks`: passing assertion, **exit 0**, 1/1 passed.
- Migrated all eight original parser cases, preserving their names and assertions. Minimal callable stub: **2/9 passed**, seven behavior failures (source-unchanged already passed). Parser implementation: **9/9 passed**.
- Added irregular/literal rows, resource caps, real temporary-file SHA-256 invariance, UTF-8 boundaries, and delayed cancellation: **11/13 passed**, with resource/file-cap failures before implementation; then **13/13 passed**.
- Added cache, header/keyboard/copy model, wrapping search, cancellation/stale-generation behavior: **13/17 passed**, four behavior failures against stubs; then **17/17 passed**.
- Added local-file/workbook routing policy: **17/18 passed** before enforcement, then **18/18 passed**.
- Benchmark contract check initially failed parsing the empty stub output. Implementation passed dimension, preview timing, SHA-256, and measured-RSS assertions.
- Bundle check initially failed because Info.plist was absent. Packaging then passed Viewer/Alternate CSV registration, minimum OS, arm64 executable, and code-signature checks.
- Actual 100 MB benchmark initially peaked at **525,942,784 bytes RSS**, failing the fixture memory regression ceiling of `3 × input bytes + 64 MiB`. Bounded autorelease pools around Foundation chunk reads/hash updates and snapshot preallocation reduced this substantially; both fixture checks now pass.

The executable checks exercise the core behavior used by the UI; they do not simulate AppKit events or establish visual correctness. No tests were skipped because of unavailable frameworks. Historical XCTest failure was an environment failure, not behavior RED. The RED/GREEN counts above came from executed assertions; raw final results are in `docs/evidence/`.

## Commands

All SwiftPM commands use these settings (the wrapper supplies them):

```sh
mkdir -p .build/cache .build/clang .build/tmp
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang"
export TMPDIR="$PWD/.build/tmp"
swift run --disable-sandbox --cache-path "$PWD/.build/cache" TableCoreChecks
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release
scripts/build-app.sh
scripts/swift-local.sh build
scripts/check-bench.sh
scripts/make-fixtures.py
.build/release/TableBench .build/fixtures/10MB.csv
.build/release/TableBench .build/fixtures/100MB.csv
python3 scripts/check-fixture-results.py
```

The `--prove-failure` mode remains available as a harness regression check and must exit 1. SwiftPM warns that user-level configuration/security caches are unwritable; repository-local build/cache paths work. The local bundle is ad-hoc signed, not notarized or globally installed.

## Benchmark method and limits

Fixtures are generated locally by `scripts/make-fixtures.py`. Each record has ten fields and exactly 100 encoded bytes. Sizes use decimal MB: 10,000,000 and 100,000,000 bytes. Dimensions include one header record: 100,000 × 10 and 1,000,000 × 10 (99,999 and 999,999 data rows). These regular numeric-text fixtures measure the indexing path; quotes, Unicode, multiline, and irregular data are covered by behavior checks, not these throughput fixtures.

Each release executable runs in a fresh process. `readSeconds` measures the same capped snapshot reader used by the app; `indexSeconds` excludes reading; `firstPreviewSeconds` includes reading, full indexing, and decoding/caching the first 50 records. This is **core preview readiness, not time to a painted AppKit window**. Peak RSS is macOS `getrusage(RUSAGE_SELF).ru_maxrss` in bytes for the whole benchmark process, including SHA-256 passes. Input hashes before/after match. Hashing occurs before timed reading, warming filesystem caches; results are single runs, not cold-I/O guarantees or statistical medians. The cache contains 50 rows, 26,900 accounted bytes, after either preview.

See the JSON files in [evidence](evidence/) for exact timings and hashes. Final benchmark summary is in STATUS.md.

## Parent GUI QA still required

Open the built app on a graphical desktop. Verify open panel, dropping onto empty/populated windows, Finder Open With, and two independent file windows. Check horizontal/vertical scrolling, column resizing, arrow/Tab navigation, selected-cell highlight, literal pasteboard copy, inspector newlines, header/delimiter changes, find/wrap/no-match, cancellation during large loads/search, and window closure while work is pending. Check malformed/unsupported files and a UTF-8 file with irregular rows. No GUI launch, visual QA, or event-level UI automation is claimed by this run.

## Single source diff review

Reviewed the source/build-script diff once. Fixed empty-window drop coverage by registering the root view, retained the prior selection while moving so the old highlighted row is refreshed, cleared table selection when rebuilding columns, and corrected cancellation status/title. These AppKit wiring fixes are compile-verified; their graphical behavior is part of the parent checklist above. The final full check/build/bundle/benchmark rerun follows these fixes.

Final outcomes: `swift run TableCoreChecks` (with the documented flags) passed 18/18; `swift build -c release`, `scripts/build-app.sh`, debug build, benchmark contract, and both actual fixture checks passed. Logs: [checks](evidence/checks-final.log), [release](evidence/release-final.log), [bundle](evidence/bundle-final.log), [benchmark contract](evidence/bench-contract-final.log), [fixture checks](evidence/fixtures-final.log).

The final local commit attempt failed: Git could not create `.git/index.lock` because the sandbox grants only read access to `.git`. No commit was created; implementation and artifacts remain available in the workspace.
