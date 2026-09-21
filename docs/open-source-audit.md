# Rowlight open-source readiness audit

Date: 2026-09-21. Repository: `kevindrafts/tableview`. Audited baseline: `5639cff`, plus the local Rowlight rebrand.

## Initial audit result

**No credentials detected in the audited material. Not yet ready to describe as open source: a license still needs to be chosen.** This is a bounded credential/privacy audit, not a guarantee that all secrets are absent or a comprehensive application-security review.

## Scope and method

- Fetched origin refs and tags. All reachable Git history: 3 commits and 46 unique file blobs, including historical/deleted material and both preview tags.
- Current source/documentation/build scripts plus the two pre-existing local result notes: 34-file snapshot before adding this report.
- Gitleaks 8.30.1, downloaded from its official GitHub release and verified against the published archive SHA-256 checksum. Default rules, redacted reporting, `git --log-opts="--all --full-history"`, and directory scans. No project-specific allowlists were added.
- Independent scan of every reachable Git blob and the working snapshot for private keys, GitHub/AWS/API tokens, JWTs, credential assignments, credentials embedded in URLs, local home paths, and email addresses. Only rule names, file locations, and counts were reported.
- Downloaded both existing GitHub release assets: `Tableview-v0.1.0-preview.1-arm64.zip` and `Tableview-v0.1.1-preview.1-arm64.zip`. Reviewed archive filenames and scanned text plus printable strings extracted from binary files with Gitleaks. Binary string scanning cannot detect every encoded or encrypted secret.
- Read repository visibility, releases, issues/pull requests, Actions artifacts, repository Actions secret names, Actions variable names, environments, and secret-scanning availability. Secret values were never requested.

## Findings

1. **Credential scans passed:** Gitleaks returned zero findings for Git history, current files, and release contents. The independent credential patterns also found no matches.
2. **Repository is private.** No visibility changes were made.
3. **No license is configured or present.** Select a license and copyright holder before publishing as open source. MIT was discussed but has not been authorized or added.
4. **Local home paths occur in historical logs and result notes.** Tracked log files in the current working tree now use `<HOME>` in place of the original home directory. Existing history and old release binaries may still contain machine/build paths. This cleanup does not erase history.
5. **Commit author names/emails are Git metadata.** They become public along with history. Review whether retaining that attribution is acceptable before changing visibility. No history was rewritten.
6. **Two historical preview releases exist.** Both contain only app-bundle entries (9 per ZIP), with no credential-like filenames. They use the old Tableview name and ad-hoc signing. They would become accessible if the repository becomes public; do not present them as the official signed Rowlight release.
7. **GitHub surfaces:** no issues/PRs, Actions artifacts, repository Actions secrets, repository Actions variables, or environments were returned. Pages and wiki are disabled. Repository secret scanning is disabled (the alerts endpoint reported this explicitly); no GitHub-native clean-scan claim is made. Organization/account-wide secrets and private systems outside this repository were not audited.
8. **Dependency surface:** SwiftPM declares no external package dependencies. This is not a full copyright or asset-provenance review.

## Changes made

- Rebranded the executable/package/app/menu/accessibility labels and current build documentation to Rowlight, preview 0.2.0 build 3.
- Added ignore rules for local task notes, environment files, common signing-certificate exports, provisioning profiles, and Apple API-key filenames. Ignore rules are preventive only; they do not remove already-tracked history or replace scanning.
- Sanitized current tracked logs' home paths. Preserved historical branding in evidence and left old releases untouched.

## Publication follow-up

The maintainer authorized completing the open-source launch after reviewing these findings.

- Selected the MIT license with the project contributor copyright notice. Added contribution and private security-reporting guidance.
- Retained existing history, attribution, and historical machine paths. No credentials were detected; these low-sensitivity historical details do not justify a destructive history rewrite. Current tracked log files remain sanitized.
- Retained the legacy ad-hoc-signed Tableview previews, clearly identified as legacy development builds. A new source-only Rowlight preview supersedes them; signed binary distribution awaits the LLC's Apple signing setup.
- Prepared a macOS build/core-check CI template and a checksum-verified Gitleaks history scan in docs/ci/checks.yml. The token was rejected for lack of workflow permission, so the template is not installed or active. When enabled, it has read-only repository permissions and does not persist checkout credentials. Local checks and final credential scans passed.
- The repository was renamed to `kevindrafts/rowlight` but remains private. A source-only release is prepared as a draft. Automatic approval review requires explicit maintainer approval before exposing retained history, legacy release files, and historical machine-path metadata. GitHub secret scanning, push protection, and private vulnerability reporting remain pending publication. Branch protection was attempted but GitHub requires Pro or a public repository on the current plan; no paid upgrade was performed.
- The exact release commit is scanned before the visibility change. Scan results are a bounded finding, not a guarantee of absence.

No Apple credentials were added to Git. Repository visibility changes do not publish GitHub Actions secret values. Account/organization systems outside this repository remain outside audit scope.
