#!/usr/bin/env python3
import json
for mb in (10, 100):
    with open(f'docs/evidence/bench-{mb}MB.json') as f:
        p = json.load(f)
    assert p['bytes'] == mb * 1_000_000
    assert p['records'] == mb * 10_000 and p['columns'] == 10
    assert p['sourceSHA256Before'] == p['sourceSHA256After']
    assert p['firstPreviewSeconds'] >= p['indexSeconds']
    assert p['cacheRows'] <= 128 and p['cacheAccountedBytes'] <= 8 * 1024 * 1024
    assert p['peakRSSBytes'] < p['bytes'] * 3 + 64 * 1024 * 1024, f'{mb}MB fixture retains too much memory: {p["peakRSSBytes"]}'
    print(f'PASS {mb}MB fixture dimensions, hash, timings, cache and RSS bounds')
