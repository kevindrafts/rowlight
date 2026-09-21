# Security policy

## Reporting a vulnerability

Use GitHub's private **Report a vulnerability** feature:
https://github.com/kevindrafts/rowlight/security/advisories/new

Do not disclose credentials, sensitive sample files, or exploitable details in a public issue. Include a minimal synthetic reproduction, affected version, macOS version, and the impact you observed. If private reporting is unavailable, open an issue asking the maintainer for a private reporting channel without including vulnerability details.

Rowlight is an early preview. Security fixes target the latest main branch and newest Rowlight preview; old Tableview previews are not maintained separately. We do not promise a response SLA.

## Releases and credentials

Builds produced by the local script are ad-hoc signed, not Apple-notarized. Official Developer ID-signed downloads will be identified explicitly in their release notes. Keep Apple signing keys and credentials out of Git and use only protected release environments for future automated signing.

A pre-publication credential audit is documented in docs/open-source-audit.md. Passing a scanner does not prove that software is free of vulnerabilities or that every possible secret has been detected.
