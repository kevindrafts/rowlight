#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/fixtures
printf 'id,note\n001,"hello\nworld"\n' > .build/fixtures/bench-check.csv
.build/debug/TableBench .build/fixtures/bench-check.csv > .build/bench-check.json
python3 - <<'PY'
import json
with open('.build/bench-check.json') as f:
    p = json.load(f)
assert p['records'] == 2 and p['columns'] == 2
assert p['previewRows'] == 2 and p['firstCell'] == 'id'
assert p['firstPreviewSeconds'] >= p['indexSeconds'] >= 0
assert p['sourceSHA256Before'] == p['sourceSHA256After']
assert p['peakRSSBytes'] > 0
print('PASS benchmark dimensions, preview timing, file hash invariance, RSS')
PY
