# Desktop check — September 21, 2026

Rebuilt `dist/Tableview.app` from the working tree and restarted the app. The previously running build lacked the source's pinned row numbers and updated cell selection; the rebuilt app displays both.

Changes:
- Centered welcome screen with a table symbol, Open File button, drag-and-drop guidance, and the open shortcut. The unused grid and inspector are hidden until a file is opened.
- Standard Cut/Paste Edit menu commands, enabling Command-V in Find. The data grid and inspector remain read-only.

Desktop verification using `docs/evidence/gui-smoke.csv`:
- Visually inspected the welcome screen and loaded grid in light appearance.
- Welcome Open File button opens the native file picker; the fixture loads in its own window.
- Click selection and arrow navigation update the selected cell and inspector.
- Leading-zero ID `001`, quoted comma, multiline field, and long identifier appear literally.
- Inspector preserves the multiline field's line break.
- Searching `line two` locates the multiline cell and wraps to it.
- Header toggle changes the data row count from 3 to 4 and clears selection; restoring it returns to 3 rows.
- After the menu fix, Command-C from the ID cell followed by Command-V in Find yields exactly `001`.

Automated verification: 21/21 core checks, AppKit UI self-checks, release build, bundle metadata/signature checks, and `git diff --check` passed. AppKit checks were rerun after the menu change.

Scope: a small repository fixture, not a broad real-world file corpus. No new large-file benchmarks, VoiceOver session, drag-and-drop interaction, or visual dark-mode review were performed. Existing UI self-checks exercise light/dark drawing and gutter scroll geometry.

## Design pass

Added a document heading, secondary file metadata, a quieter toolbar, transient import options, content-aware initial column widths (bounded to 110–360 points), comfortable/compact row density, padded system-font cells with optional monospaced text, and a compact/expanded full-value inspector. Cancel is visible only while work is running. Empty rows no longer extend the table's striping.

Checked a generated 12-row project sample on the desktop: file loading, content widths, both densities, multiline search, inspector expansion, header switching, and monospaced display. Screenshots are saved under `dist/screenshots/redesign-*.jpg`; they show synthetic sample data. Extended the AppKit self-checks for welcome visibility, inspector heights, bounded column widths, and row-density switching. Core checks (21/21), AppKit checks, release build, and bundle checks pass. Sorting, filtering, frozen data columns, multi-cell selection, and a freely resizable inspector are not part of this design pass.
