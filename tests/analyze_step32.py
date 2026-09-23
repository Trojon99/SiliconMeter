#!/usr/bin/env python3
"""Summarize Step 3.2 long-run trace and the matching SQLite run."""
import json
from datetime import datetime
from pathlib import Path
import sqlite3
import statistics
import sys

trace = Path(sys.argv[1])
db = Path.home() / 'Library/Application Support/Compute Monitor/telemetry.sqlite3'
rows = [json.loads(line) for line in trace.open()]
samples = [r for r in rows if r.get('kind') == 'sample']
states = [r for r in rows if r.get('kind') == 'database']
meta = next(r for r in rows if r.get('kind') == 'metadata')
after = next((r for r in rows if r.get('kind') == 'database_after'), None)
summary = {'trace': str(trace), 'binary_sha256': meta['binary_sha256'],
           'source_sha256': meta['source_sha256'], 'sample_count': len(samples),
           'database_before': meta['database_before'], 'database_after': after,
           'title_mismatches': sum(not r['title_matches_snapshot'] for r in samples),
           'tick_gaps': sum(b['tick'] != a['tick'] + 1 for a, b in zip(samples, samples[1:])),
           'slow_cadence_correct': all(('gpuPower' in r['readings']) == (r['tick'] % 3 == 0)
                                       and r['slow_count'] == 1 + r['tick']//3 for r in samples),
           'selected_modes': sorted({r['selected'] for r in samples}),
           'toggle_count': samples[-1]['toggle_count'],
           'selection_count': samples[-1]['selection_count'],
           'database_query_errors': [r for r in states if 'query_error' in r['counts']]}
baseline_path = trace.parent / 'step31-2026-09-23-summary.json'
if baseline_path.exists():
    baseline = json.loads(baseline_path.read_text())
    summary['logging_off_baseline'] = {
        phase: {'cpu_percent_one_core': baseline['phases'][phase]['cpu_percent_one_core'],
                'rss_first_bytes': baseline['phases'][phase]['rss_first_bytes'],
                'rss_last_bytes': baseline['phases'][phase]['rss_last_bytes'],
                'sampling_latency_ms': baseline['phases'][phase]['sampling_latency_ms']}
        for phase in ('idle', 'gpu_load', 'recovery')}

def quantile(values, q):
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * q)] if ordered else None

summary['phases'] = {}
def ui_kind(row):
    t = (row['elapsed_s'] - 30) % 600
    if 60 <= t < 120 or 270 <= t < 420 or 570 <= t < 600:
        return 'closed_steady' if not row['popover_open'] else None
    if 200 <= t < 240 or 500 <= t < 540:
        return 'open_steady' if row['popover_open'] else None
    if 120 <= t < 180 or 420 <= t < 480:
        return 'cycling'
    return None

summary['ui_cpu'] = {}
for phase in ('idle', 'gpu_load', 'recovery'):
    group = [r for r in samples if r['phase'] == phase]
    if not group:
        continue
    duration = group[-1]['elapsed_s'] - group[0]['elapsed_s']
    cpu = group[-1]['resources']['cpu_s'] - group[0]['resources']['cpu_s']
    latency = [r['sampling_latency_ms'] for r in group]
    interval = [r['tick_interval_s'] for r in group]
    failures = {}
    for r in group:
        for key, metric in r['readings'].items():
            if metric['status'] in ('unavailable', 'invalid', 'stale'):
                failures[key + ':' + metric['status']] = failures.get(key + ':' + metric['status'], 0) + 1
    summary['phases'][phase] = {
        'duration_s': duration, 'fast_rows': len(group), 'cpu_s': cpu,
        'cpu_percent_one_core': 100 * cpu / duration,
        'rss_first_bytes': group[0]['resources']['rss_bytes'],
        'rss_last_bytes': group[-1]['resources']['rss_bytes'],
        'rss_peak_bytes': max(r['resources']['rss_bytes'] for r in group),
        'peak_rss_bytes': max(r['resources']['peak_rss_bytes'] for r in group),
        'latency_ms_p50': quantile(latency, .5), 'latency_ms_p95': quantile(latency, .95),
        'latency_ms_max': max(latency), 'telemetry_nonusable': failures,
        'tick_interval_s_p50': quantile(interval, .5), 'tick_interval_s_p95': quantile(interval, .95),
        'tick_interval_s_max': max(interval),
        'ui_actions': sum(r['ui_action'] != 'none' for r in group),
        'interrupt_wakeups_delta': group[-1]['resources']['interrupt_wakeups'] - group[0]['resources']['interrupt_wakeups'],
        'package_idle_wakeups_delta': group[-1]['resources']['package_idle_wakeups'] - group[0]['resources']['package_idle_wakeups']}
    for kind in ('closed_steady', 'open_steady', 'cycling'):
        pairs = [(a, b) for a, b in zip(samples, samples[1:])
                 if a['phase'] == b['phase'] == phase and ui_kind(a) == ui_kind(b) == kind]
        span = sum(b['elapsed_s'] - a['elapsed_s'] for a, b in pairs)
        cpu_part = sum(b['resources']['cpu_s'] - a['resources']['cpu_s'] for a, b in pairs)
        summary['ui_cpu'][f'{phase}:{kind}'] = {'duration_s': span,
                                               'cpu_percent_one_core': 100 * cpu_part / span if span else None}

if baseline_path.exists():
    summary['logging_off_ui_cpu'] = {key: value['cpu_percent_one_core']
                                     for key, value in baseline['ui_cpu'].items()}

summary['five_minute_bins'] = []
for i in range(6):
    group = [r for r in samples if 30 + 300*i <= r['elapsed_s'] < 30 + 300*(i+1)]
    if group:
        duration = group[-1]['elapsed_s'] - group[0]['elapsed_s']
        cpu = group[-1]['resources']['cpu_s'] - group[0]['resources']['cpu_s']
        summary['five_minute_bins'].append({'bin': i, 'samples': len(group),
            'rss_first_bytes': group[0]['resources']['rss_bytes'],
            'rss_last_bytes': group[-1]['resources']['rss_bytes'],
            'rss_peak_bytes': max(r['resources']['rss_bytes'] for r in group),
            'cpu_percent_one_core': 100 * cpu / duration})

with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as c:
    c.row_factory = sqlite3.Row
    trace_start_ms = int(datetime.fromisoformat(meta['utc']).timestamp() * 1000)
    run = c.execute('SELECT * FROM app_runs WHERE start_utc_ms BETWEEN ? AND ? '
                    'ORDER BY abs(start_utc_ms - ?) LIMIT 1',
                    (trace_start_ms - 5000, trace_start_ms + 60000, trace_start_ms)).fetchone()
    if run is None:
        raise SystemExit('No app_runs row matches the trace launch time')
    runid = run['run_id']
    summary['run'] = dict(run)
    summary['journal_mode'] = c.execute('PRAGMA journal_mode').fetchone()[0]
    summary['integrity_check'] = c.execute('PRAGMA integrity_check').fetchone()[0]
    summary['rows'] = {table: c.execute(f'SELECT count(*) FROM {table} WHERE run_id=?', (runid,)).fetchone()[0]
                       for table in ('fast_samples', 'slow_samples', 'events', 'writer_batches')}
    batch = c.execute('SELECT sum(fast_rows), sum(slow_rows), sum(event_rows), avg(duration_ms), max(duration_ms) FROM writer_batches WHERE run_id=?', (runid,)).fetchone()
    summary['batch'] = dict(zip(('fast_rows', 'slow_rows', 'event_rows', 'precommit_duration_ms_avg', 'precommit_duration_ms_max'), batch))
    summary['quality_counts'] = {}
    for table, fields in (('fast_samples', ('cpu_total', 'cpu_p', 'cpu_e', 'gpu_active', 'gpu_frequency_mhz')),
                          ('slow_samples', ('gpu_power_w', 'cpu_tp05_c', 'gpu_tg05_c', 'physical_b',
                                            'free_b', 'active_b', 'inactive_b', 'wired_b', 'compressed_b',
                                            'swap_used_b', 'swap_in_pages_s', 'swap_out_pages_s', 'pressure', 'thermal'))):
        for field in fields:
            summary['quality_counts'][field] = dict(c.execute(
                f'SELECT {field}_quality, count(*) FROM {table} WHERE run_id=? GROUP BY {field}_quality', (runid,)))

if after and states:
    def disk_total(state):
        return state['sizes_bytes']['main'] + state['sizes_bytes']['-wal'] + state['sizes_bytes']['-shm']
    before_size = disk_total(meta['database_before'])
    final_size = disk_total(after)
    peak_size = max(disk_total(s) for s in states)
    duration_h = (samples[-1]['elapsed_s'] - samples[0]['elapsed_s']) / 3600
    growth = final_size - before_size
    summary['disk'] = {'before_total_bytes': before_size, 'final_total_bytes': final_size,
                       'peak_runtime_total_bytes': peak_size,
                       'peak_runtime_wal_bytes': max(s['sizes_bytes']['-wal'] for s in states),
                       'observed_growth_bytes': growth, 'observed_hours': duration_h,
                       'estimated_bytes_1h': growth / duration_h,
                       'estimated_bytes_24h': growth / duration_h * 24,
                       'estimated_bytes_7d': growth / duration_h * 24 * 7,
                       'estimated_bytes_30d': growth / duration_h * 24 * 30}

out = trace.with_name(trace.stem + '-summary.json')
out.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
print(out)
