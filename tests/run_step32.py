#!/usr/bin/env python3
"""Thirty-minute production-source history run with external SQLite observations."""
import datetime
import hashlib
import json
import os
import sqlite3
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / '.build/ComputeMonitorReview.app/Contents/MacOS/ComputeMonitor'
PROBE = ROOT / 'experiments/bin/telemetry-probe'
DB = Path.home() / 'Library/Application Support/Compute Monitor/telemetry.sqlite3'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def database_state():
    sizes = {suffix or 'main': (Path(str(DB) + suffix).stat().st_size if Path(str(DB) + suffix).exists() else 0)
             for suffix in ('', '-wal', '-shm')}
    counts = {}
    if DB.exists():
        try:
            with sqlite3.connect(f'file:{DB}?mode=ro', uri=True, timeout=1) as connection:
                counts = {table: connection.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
                          for table in ('app_runs', 'fast_samples', 'slow_samples', 'events', 'writer_batches')}
                counts['integrity'] = connection.execute('PRAGMA quick_check').fetchone()[0]
        except sqlite3.Error as error:
            counts = {'query_error': str(error)}
    return {'sizes_bytes': sizes, 'counts': counts}


def main():
    path = Path(sys.argv[1])
    short = '--short' in sys.argv
    app = load = None
    with path.open('x') as output:
        def emit(row):
            output.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n')
            output.flush()
        emit({'kind': 'metadata', 'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'short_preflight': short, 'warmup_s': 30, 'phase_s': 600,
              'database_before': database_state(),
              'source_sha256': {str(p.relative_to(ROOT)): sha(p) for p in
                  [ROOT/'app/ComputeMonitor.swift', ROOT/'app/HistoryLogger.swift', ROOT/'app/TelemetryBackend.m',
                   ROOT/'app/TelemetryBackend.h', ROOT/'tests/Step31Review.swift',
                   ROOT/'tests/Step31Diagnostics.inc']},
              'binary_sha256': sha(APP), 'load_sha256': sha(PROBE),
              'historical_trace_sha256': sha(ROOT/'experiments/results/step26-2026-09-23.jsonl'),
              'macos': subprocess.check_output(['sw_vers'], text=True),
              'instrumentation': 'test-only stdout capture; normal collector/scheduler/AppKit paths'})
        env = os.environ.copy()
        if short:
            env['STEP31_DURATION'] = '15'
        with path.with_suffix('.stderr.txt').open('x') as errors:
            try:
                app = subprocess.Popen([str(APP)], stdout=subprocess.PIPE, stderr=errors, text=True, env=env)
                emit({'kind': 'launch', 'pid': app.pid})
                for line in app.stdout:
                    row = json.loads(line)
                    elapsed = row['elapsed_s']
                    row['phase'] = 'warmup' if elapsed < 30 else 'idle' if elapsed < 630 else 'gpu_load' if elapsed < 1230 else 'recovery'
                    emit(row)
                    if not short and elapsed >= 630 and load is None:
                        load = subprocess.Popen([str(PROBE), '--load', 'gpu-heavy', '--duration', '598'],
                                                stdout=subprocess.DEVNULL, stderr=errors)
                        emit({'kind': 'load_start', 'elapsed_s': elapsed, 'pid': load.pid})
                        print('GPU load started', load.pid, flush=True)
                    if load is not None and load.poll() is not None and not getattr(main, 'load_reported', False):
                        emit({'kind': 'load_end', 'elapsed_s': elapsed, 'returncode': load.returncode})
                        main.load_reported = True
                        print('GPU load ended', load.returncode, flush=True)
                    if row['tick'] % 15 == 0:
                        emit({'kind': 'database', 'elapsed_s': elapsed, **database_state()})
                    if row['tick'] % 30 == 0:
                        print('progress', round(elapsed, 1), row['phase'], row['resources']['rss_bytes'], flush=True)
                code = app.wait(timeout=10)
                emit({'kind': 'exit', 'pid': app.pid, 'returncode': code})
                emit({'kind': 'database_after', **database_state()})
                if code:
                    raise SystemExit(code)
            finally:
                for process in (load, app):
                    if process is not None and process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
    print('saved', path, flush=True)


if __name__ == '__main__':
    main()
