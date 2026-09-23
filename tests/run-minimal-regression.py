#!/usr/bin/env python3
"""Observe an already running production app for 15 minutes without instrumenting it."""
from pathlib import Path
import datetime
import json
import sqlite3
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DB = Path.home() / 'Library/Application Support/Compute Monitor/telemetry.sqlite3'
APP = str(ROOT / 'app/ComputeMonitor.app/Contents/MacOS/ComputeMonitor')
OUT = ROOT / 'docs/results/minimal-v01-regression.jsonl'

def process():
    lines = subprocess.check_output(['ps', '-axo', 'pid,ppid,%cpu,rss,args'], text=True).splitlines()[1:]
    for line in lines:
        parts = line.split(None, 4)
        if len(parts) == 5 and parts[4] == APP:
            return {'pid': int(parts[0]), 'ppid': int(parts[1]), 'cpu_percent': float(parts[2]),
                    'rss_kb': int(parts[3])}
    return None

def database():
    with sqlite3.connect(f'file:{DB}?mode=ro', uri=True, timeout=5) as c:
        counts = {name: c.execute(f'SELECT count(*) FROM {name}').fetchone()[0]
                  for name in ('app_runs','fast_samples','slow_samples','events','writer_batches')}
        return {'version': c.execute('PRAGMA user_version').fetchone()[0],
                'integrity': c.execute('PRAGMA integrity_check').fetchone()[0], 'counts': counts,
                'sizes': {suffix or 'main': (Path(str(DB)+suffix).stat().st_size if Path(str(DB)+suffix).exists() else 0)
                          for suffix in ('','-wal','-shm')}}

def emit(file, row):
    file.write(json.dumps(row, ensure_ascii=False, sort_keys=True)+'\n')
    file.flush()

assert not OUT.exists(), f'{OUT} already exists'
with OUT.open('x') as output:
    initial = process()
    assert initial is not None, 'production app not running'
    pid = initial['pid']
    start = time.monotonic()
    emit(output, {'kind': 'start', 'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'pid': pid, 'database': database()})
    while True:
        now = time.monotonic()
        current = process()
        assert current is not None and current['pid'] == pid, 'production app exited during regression'
        emit(output, {'kind': 'sample', 'elapsed_s': round(now-start, 1), 'process': current, 'database': database()})
        if now-start >= 900: break
        time.sleep(min(30, 900-(now-start)))
    children = subprocess.check_output(['ps', '-axo', 'ppid='], text=True).splitlines()
    child_count = sum(int(line.strip()) == pid for line in children if line.strip().isdigit())
    connections = subprocess.run(['lsof', '-nP', '-a', '-p', str(pid), '-i'], text=True, capture_output=True).stdout
    emit(output, {'kind': 'end', 'elapsed_s': round(time.monotonic()-start, 1),
                  'child_processes': child_count, 'network_connections': max(0, len(connections.splitlines())-1),
                  'database': database()})
print(f'REGRESSION PASS {OUT}')
