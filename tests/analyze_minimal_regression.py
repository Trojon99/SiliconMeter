#!/usr/bin/env python3
"""Summarize the 15-minute ordinary-build observation trace."""
from pathlib import Path
import json
import statistics
import sys

ROOT = Path(__file__).resolve().parents[1]
trace = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'docs/results/minimal-v01-regression.jsonl'
rows = [json.loads(line) for line in trace.read_text().splitlines()]
start, end = rows[0], rows[-1]
samples = [r for r in rows if r['kind'] == 'sample']
assert start['kind'] == 'start' and end['kind'] == 'end'
assert 900 <= end['elapsed_s'] <= 1200
assert all(r['process']['pid'] == start['pid'] for r in samples)
version = start['database']['version']
assert all(r['database']['version'] == version and r['database']['integrity'] == 'ok' for r in rows)
assert end['child_processes'] == 0 and end['network_connections'] == 0
counts_before = start['database']['counts']
counts_after = end['database']['counts']
assert counts_after['fast_samples'] > counts_before['fast_samples']
assert counts_after['slow_samples'] > counts_before['slow_samples']
assert counts_after['writer_batches'] > counts_before['writer_batches']
cpu = [r['process']['cpu_percent'] for r in samples]
rss = [r['process']['rss_kb'] / 1024 for r in samples]
late = [r['process']['rss_kb'] / 1024 for r in samples if r['elapsed_s'] >= 600]
summary = {
    'duration_s': end['elapsed_s'], 'pid': start['pid'], 'observations': len(samples),
    'version': version, 'integrity_every_observation': True,
    'counts_before': counts_before, 'counts_after': counts_after,
    'count_increase': {name: counts_after[name]-count for name, count in counts_before.items()},
    'cpu_percent_of_one_core': {'mean': round(statistics.mean(cpu), 3),
                                'median': statistics.median(cpu), 'max': max(cpu)},
    'rss_mb': {'initial': round(rss[0], 2), 'maximum': round(max(rss), 2),
               'final': round(rss[-1], 2), 'late_range': round(max(late)-min(late), 2)},
    'child_processes': end['child_processes'], 'network_connections': end['network_connections'],
}
out = trace.with_name(trace.stem + '-summary.json')
out.write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(summary, ensure_ascii=False))
