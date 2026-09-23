#!/usr/bin/env python3
"""Kill only apps launched by this script after a committed history batch."""
import datetime
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'app/ComputeMonitor.app/Contents/MacOS/ComputeMonitor'
DB = Path.home() / 'Library/Application Support/Compute Monitor/telemetry.sqlite3'
OUT = Path(sys.argv[1])


def connection():
    return sqlite3.connect(f'file:{DB}?mode=ro', uri=True, timeout=2)


def latest_run():
    with connection() as c:
        row = c.execute('SELECT run_id, start_utc_ms FROM app_runs ORDER BY start_utc_ms DESC LIMIT 1').fetchone()
        return row


def run_once(previous):
    app = subprocess.Popen([str(APP)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 50
        while time.monotonic() < deadline:
            if app.poll() is not None:
                raise RuntimeError(f'app exited early: {app.returncode}, {app.stderr.read().decode()}')
            current = latest_run()
            if current and current[0] != previous:
                with connection() as c:
                    fast = c.execute('SELECT count(*) FROM fast_samples WHERE run_id=?', (current[0],)).fetchone()[0]
                    batches = c.execute('SELECT count(*) FROM writer_batches WHERE run_id=?', (current[0],)).fetchone()[0]
                if fast >= 10 and batches >= 1:
                    break
            time.sleep(.5)
        else:
            raise RuntimeError('no committed app batch within 50 seconds')
        # At least two later 2-second samples should be queued but not yet flushed.
        time.sleep(5)
        with connection() as c:
            before = {'fast': c.execute('SELECT count(*) FROM fast_samples WHERE run_id=?', (current[0],)).fetchone()[0],
                      'batches': c.execute('SELECT count(*) FROM writer_batches WHERE run_id=?', (current[0],)).fetchone()[0]}
        app.kill()
        app.wait(timeout=10)
        with connection() as c:
            after = {'fast': c.execute('SELECT count(*) FROM fast_samples WHERE run_id=?', (current[0],)).fetchone()[0],
                     'batches': c.execute('SELECT count(*) FROM writer_batches WHERE run_id=?', (current[0],)).fetchone()[0],
                     'run_end': c.execute('SELECT end_utc_ms FROM app_runs WHERE run_id=?', (current[0],)).fetchone()[0],
                     'integrity': c.execute('PRAGMA integrity_check').fetchone()[0],
                     'journal_mode': c.execute('PRAGMA journal_mode').fetchone()[0]}
        assert before['fast'] == after['fast'] and before['batches'] == after['batches']
        assert after['run_end'] is None and after['integrity'] == 'ok' and after['journal_mode'] == 'wal'
        return {'pid': app.pid, 'run_id': current[0], 'before_kill': before, 'after_kill': after}
    finally:
        if app.poll() is None:
            app.kill(); app.wait(timeout=10)


previous = latest_run()[0] if DB.exists() else None
first = run_once(previous)
second = run_once(first['run_id'])
assert first['run_id'] != second['run_id'] and second['after_kill']['fast'] >= 10
OUT.write_text(json.dumps({'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                           'first': first, 'reopened': second}, indent=2) + '\n')
print('APP_CRASH_CHECK PASS', OUT)
