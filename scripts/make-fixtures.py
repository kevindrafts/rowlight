#!/usr/bin/env python3
"""Deterministic decimal-MB CSV fixtures, exactly 100 bytes per ten-field record."""
from pathlib import Path
root = Path('.build/fixtures')
root.mkdir(parents=True, exist_ok=True)
header = (','.join(f'column{i:03}' for i in range(10)) + '\n').encode()
row = (','.join(f'{i:09}' for i in range(10)) + '\n').encode()
assert len(header) == len(row) == 100
for size in (10_000_000, 100_000_000):
    path = root / f'{size // 1_000_000}MB.csv'
    with path.open('wb') as f:
        f.write(header)
        remaining = size // 100 - 1
        while remaining:
            count = min(remaining, 10_000)
            f.write(row * count)
            remaining -= count
    assert path.stat().st_size == size
    print(f'{path}: {size} bytes, {size // 100} records including header, 10 columns')
