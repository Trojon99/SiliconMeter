#!/usr/bin/env python3
"""Summarize the externally observed ordinary-binary Network A/B run."""
from pathlib import Path
from datetime import datetime
import json

root = Path(__file__).resolve().parents[1]
data = json.loads((root/'docs/results/network-ab.json').read_text())
a,b = data['A'],data['B']
assert 600 <= a['duration_s'] <= 660 and 900 <= b['duration_s'] <= 960
assert a['network_enabled'] is False and b['network_enabled'] is True
assert a['network_quality']['unavailable'] == a['fast_rows']
assert b['network_quality']['measured'] > 0
assert a['fast_rows'] > 200 and b['fast_rows'] > 300
assert 1.5 < a['fast_cadence_s']['median'] < 3
assert 1.5 < b['fast_cadence_s']['median'] < 3
summary = {
    'same_binary_sha256': data['binary_sha256'],
    'A_disabled': {k:a[k] for k in ('duration_s','cpu_s_after_warmup','cpu_percent_one_core_after_warmup',
                                'rss_mb','fast_rows','slow_rows','writer_batches','network_quality','fast_cadence_s')},
    'B_enabled': {k:b[k] for k in ('duration_s','cpu_s_after_warmup','cpu_percent_one_core_after_warmup',
                               'rss_mb','fast_rows','slow_rows','writer_batches','network_quality','fast_cadence_s',
                               'network_window_s_median','network_zero_samples')},
    'delta_one_core_cpu_percentage_points': round(b['cpu_percent_one_core_after_warmup']-a['cpu_percent_one_core_after_warmup'],3),
    'delta_final_rss_mb': round(b['rss_mb']['final']-a['rss_mb']['final'],2),
    'sampling_latency_ms': data['sampling_latency_ms'],
    'wakeups': data['wakeups'], 'energy_impact': data['energy_impact'],
}
sizes = root/'docs/results/network-db-size.jsonl'
if sizes.exists():
    rows = [json.loads(line) for line in sizes.read_text().splitlines()]
    by_phase = {row['phase']:row for row in rows}
    if 'B_start' in by_phase and 'B_end' in by_phase:
        first,last=by_phase['B_start'],by_phase['B_end']
        summary['v4_durable_growth_bytes'] = last['files']['main']-first['files']['main']
        summary['v4_growth_interval_s'] = round((datetime.fromisoformat(last['utc'])-
                                                datetime.fromisoformat(first['utc'])).total_seconds(),1)
        summary['v4_growth_mb_per_hour'] = round(summary['v4_durable_growth_bytes'] /
                                                 summary['v4_growth_interval_s']*3600/1_000_000,3)
        summary['v4_growth_projection_mb'] = {label:round(summary['v4_growth_mb_per_hour']*hours,2)
                                              for label,hours in {'hour':1,'day':24,'7_days':168,'30_days':720}.items()}
out=root/'docs/results/network-ab-summary.json'
out.write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary,ensure_ascii=False))
