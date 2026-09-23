#!/usr/bin/env python3
"""Summarize raw Step 3.1 observations; never infer unavailable counters."""
import argparse
from collections import Counter
import json
from pathlib import Path
import statistics


def stats(values):
    xs = sorted(x for x in values if x is not None)
    if not xs:
        return None
    return {'min': xs[0], 'median': statistics.median(xs), 'mean': statistics.mean(xs),
            'p95': xs[min(len(xs) - 1, int(len(xs) * .95))], 'max': xs[-1]}


def summarize(rows):
    if len(rows) < 2:
        return None
    first, last = rows[0], rows[-1]
    duration = last['elapsed_s'] - first['elapsed_s']
    cpu = last['resources']['cpu_s'] - first['resources']['cpu_s']
    qualities = Counter()
    reasons = Counter()
    values = {}
    windows = {}
    bad_ticks = Counter()
    for r in rows:
        seen = set()
        for key, metric in r['readings'].items():
            qualities[key + ':' + metric['status']] += 1
            if metric.get('reason'):
                reasons[key + ':' + metric['reason']] += 1
            if metric['status'] in ('invalid', 'stale'):
                seen.add(metric['status'])
            if 'failed' in metric.get('reason', ''):
                seen.add('failed')
            if 'baseline' in metric.get('reason', '') or 'reset' in metric.get('reason', ''):
                seen.add('baseline_reset')
            if isinstance(metric.get('value'), (int, float)):
                values.setdefault(key, []).append(metric['value'])
            if 'window_s' in metric:
                windows.setdefault(key, []).append(metric['window_s'])
        bad_ticks.update(seen)
    return {'first_elapsed_s': first['elapsed_s'], 'last_elapsed_s': last['elapsed_s'],
            'duration_s': duration, 'fast_samples': len(rows),
            'slow_samples_in_rows': sum('gpuPower' in r['readings'] for r in rows),
            'cpu_s': cpu, 'cpu_percent_one_core': 100 * cpu / duration,
            'rss_first_bytes': first['resources']['rss_bytes'], 'rss_last_bytes': last['resources']['rss_bytes'],
            'resources': {k: stats([r['resources'][k] for r in rows]) for k in
                          ['rss_bytes', 'peak_rss_bytes', 'host_refs', 'port_names', 'threads', 'children']},
            'tick_interval_s': stats([r['tick_interval_s'] for r in rows]),
            'sampling_latency_ms': stats([r['sampling_latency_ms'] for r in rows]),
            'qualities': dict(qualities), 'reasons': dict(reasons), 'bad_ticks': dict(bad_ticks),
            'metrics': {k: stats(v) for k, v in values.items()},
            'windows_s': {k: stats(v) for k, v in windows.items()},
            'interrupt_wakeups_delta': last['resources']['interrupt_wakeups'] - first['resources']['interrupt_wakeups'],
            'package_idle_wakeups_delta': last['resources']['package_idle_wakeups'] - first['resources']['package_idle_wakeups']}


def ui_kind(row):
    t = (row['elapsed_s'] - 30) % 600
    if 60 <= t < 120 or 270 <= t < 420 or 570 <= t < 600:
        return 'closed_steady' if not row['popover_open'] else None
    if 200 <= t < 240 or 500 <= t < 540:
        return 'open_steady' if row['popover_open'] else None
    if 120 <= t < 180 or 420 <= t < 480:
        return 'cycling'
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('trace', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    all_rows = [json.loads(line) for line in args.trace.read_text().splitlines()]
    rows = [r for r in all_rows if r['kind'] == 'sample']
    if not rows:
        raise SystemExit('No samples')
    result = {'metadata': all_rows[0], 'events': [r for r in all_rows[1:] if r['kind'] != 'sample'],
              'pids': sorted({r['resources']['pid'] for r in rows}),
              'complete': any(r['kind'] == 'exit' and r['returncode'] == 0 for r in all_rows),
              'overall': summarize(rows),
              'phases': {p: summarize([r for r in rows if r['phase'] == p]) for p in ('warmup', 'idle', 'gpu_load', 'recovery')},
              'five_minute_bins': {str(i): summarize([r for r in rows if 30 + i*300 <= r['elapsed_s'] < 330 + i*300]) for i in range(6)},
              'unavailable_measurements': ['Energy Impact', 'total wakeups', 'package power'],
              'selection_actions_valid': all(r['selected'] == (r['selection_count'] - 1) % 4 for r in rows if r['ui_action'] == 'toggle_and_select'),
              'title_mismatches': sum(not r['title_matches_snapshot'] for r in rows),
              'sample_sequence_contiguous': [r['tick'] for r in rows] == list(range(1, rows[-1]['tick'] + 1)),
              'slow_cadence_correct': all(('gpuPower' in r['readings']) == (r['tick'] % 3 == 0) and r['slow_count'] == 1 + r['tick']//3 for r in rows),
              'toggle_count': rows[-1]['toggle_count'], 'selection_count': rows[-1]['selection_count'],
              'selected_modes': sorted({r['selected'] for r in rows}),
              'ui_cpu': {}}
    for phase in ('idle', 'gpu_load', 'recovery'):
        for kind in ('closed_steady', 'open_steady', 'cycling'):
            pairs = [(a,b) for a,b in zip(rows, rows[1:]) if a['phase'] == b['phase'] == phase and ui_kind(a) == ui_kind(b) == kind]
            duration = sum(b['elapsed_s'] - a['elapsed_s'] for a,b in pairs)
            cpu = sum(b['resources']['cpu_s'] - a['resources']['cpu_s'] for a,b in pairs)
            result['ui_cpu'][phase + ':' + kind] = {'duration_s': duration, 'cpu_s': cpu,
                'cpu_percent_one_core': 100 * cpu / duration if duration else None}
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.write_text(text)
    else:
        print(text, end='')


if __name__ == '__main__':
    main()
