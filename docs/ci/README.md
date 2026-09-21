# Enable GitHub Actions checks

`checks.yml` is a ready-to-enable workflow template, not an active workflow.

The launch token could push normal repository files and administer the repository but could not create `.github/workflows/checks.yml`: GitHub rejected that upload because the OAuth token lacks the `workflow` scope. The launch therefore used locally verified core checks, UI checks, bundle checks, and Gitleaks scans.

A maintainer can install this template as `.github/workflows/checks.yml` through GitHub's web editor or push it using a credential authorized to manage workflows. Then verify both jobs pass before making their statuses required for merges. The template runs core checks and builds the app on macOS, and scans reachable history using checksum-verified Gitleaks on Linux. It has read-only contents permission and does not persist checkout credentials.

Do not put signing credentials in this workflow. Signed distribution needs a separate protected release workflow and the LLC's Apple signing configuration.
