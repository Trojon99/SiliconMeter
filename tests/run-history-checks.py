#!/usr/bin/env python3
"""Isolated SQLite correctness and controlled uncommitted-buffer crash check."""
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build/history-checks'
BUILD.mkdir(parents=True, exist_ok=True)
source = (ROOT / 'app/ComputeMonitor.swift').read_text().split('let app = NSApplication.shared')[0]
(BUILD / 'main.swift').write_text(source + (ROOT / 'tests/history_fixture.swift').read_text())
subprocess.run(['swiftc', '-O', '-target', 'arm64-apple-macos13.0', '-module-cache-path',
                str(ROOT / '.build/ModuleCache'), '-import-objc-header',
                str(ROOT / 'app/TelemetryBackend.h'), str(BUILD / 'main.swift'),
                str(ROOT / 'app/HistoryLogger.swift'), str(ROOT / 'app/Localization.swift'), str(ROOT / '.build/TelemetryBackend.o'), str(ROOT / '.build/NetworkSampler.o'),
                '-framework', 'AppKit', '-framework', 'IOKit', '-lsqlite3',
                '-o', str(BUILD / 'fixture')], check=True, cwd=ROOT)

with tempfile.TemporaryDirectory(prefix='compute-history-') as tmp:
    db = Path(tmp) / 'new' / 'history.sqlite3'
    def run(mode):
        return subprocess.run([str(BUILD / 'fixture'), str(db), mode], cwd=ROOT, capture_output=True, text=True)
    result = run('normal')
    assert result.returncode == 0, result.stderr
    with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as c:
        assert c.execute('PRAGMA user_version').fetchone()[0] == 4
        assert c.execute('PRAGMA journal_mode').fetchone()[0] == 'wal'
        assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert c.execute("SELECT count(*) FROM sqlite_master WHERE name='training_sessions'").fetchone()[0] == 0
        assert c.execute('SELECT count(*) FROM app_runs').fetchone()[0] == 1
        assert c.execute('SELECT count(*) FROM fast_samples').fetchone()[0] == 2
        assert c.execute('SELECT count(*) FROM slow_samples').fetchone()[0] == 1
        assert c.execute('SELECT count(*) FROM writer_batches').fetchone()[0] >= 2
        assert c.execute('SELECT cpu_e, cpu_e_quality, gpu_active, gpu_active_quality FROM fast_samples WHERE seq=1').fetchone() == (None, 'unavailable', 0.0, 'measured')
        assert c.execute('SELECT network_rx_bytes_per_sec, network_rx_bytes_per_sec_quality, network_rx_bytes_per_sec_window_s, network_tx_bytes_per_sec, network_tx_bytes_per_sec_quality FROM fast_samples WHERE seq=1').fetchone() == (1250.0, 'measured', 2.0, 0.0, 'measured')
        assert c.execute('SELECT gpu_active, gpu_active_quality FROM fast_samples WHERE seq=2').fetchone() == (None, 'stale')
        assert c.execute('SELECT gpu_power_w, gpu_power_w_quality, swap_in_pages_s, swap_in_pages_s_quality FROM slow_samples').fetchone() == (5.2, 'estimated', None, 'unavailable')
        assert {r[0] for r in c.execute('SELECT kind FROM events')} == {'app_start', 'thermal_change', 'pressure_change', 'app_graceful_stop'}
        runrow = c.execute('SELECT start_utc_ms, end_utc_ms, schema_version, macos_version, macos_build, hardware_id, logical_cores, pe_topology_verified FROM app_runs').fetchone()
        assert abs(runrow[0] / 1000 - time.time()) < 30 and runrow[1] >= runrow[0]
        assert runrow[2] == 4 and runrow[3] and runrow[4] and runrow[5] and runrow[6] > 0 and runrow[7] == 1

    result = run('resume')
    assert result.returncode == 0, result.stderr
    with sqlite3.connect(db) as c:
        assert c.execute('SELECT count(*) FROM app_runs').fetchone()[0] == 2
        assert c.execute('SELECT count(*) FROM fast_samples').fetchone()[0] == 3
        assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'

    crashdb = Path(tmp) / 'crash' / 'history.sqlite3'
    db = crashdb
    result = run('crash')
    assert result.returncode == -9, (result.returncode, result.stderr)
    with sqlite3.connect(db) as c:
        assert c.execute('SELECT count(*) FROM fast_samples').fetchone()[0] == 1
        assert c.execute('SELECT end_utc_ms FROM app_runs').fetchone()[0] is None
        assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    result = run('resume')
    assert result.returncode == 0, result.stderr
    with sqlite3.connect(db) as c:
        assert c.execute('SELECT count(*) FROM app_runs').fetchone()[0] == 2
        assert c.execute('SELECT count(*) FROM fast_samples').fetchone()[0] == 2
        assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    print('HISTORY_CHECKS PASS schema/quality/UTC/flush/reopen/WAL/readonly/crash/integrity')
