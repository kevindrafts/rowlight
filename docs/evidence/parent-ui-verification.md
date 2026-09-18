# Parent verification for 0.1.1 preview

- Independently reran TableCoreChecks: 21/21 passed.
- Bundle metadata/signature checks passed.
- Release executable AND bundled executable --ui-self-check passed with exit 0. The sandbox-only bundled exit 134 was not reproduced outside the builder sandbox.
- Reviewed native UI diff and ran git diff --check (passed).
- Launched built app with GUI smoke CSV via Launch Services.
- Screenshot capture still returns 0x0 with no elements; no visual acceptance or manual interaction coverage is claimed.
