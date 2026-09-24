#!/usr/bin/env python3
"""Deterministic v4 retention, boundary, WAL, batching, and crash checks."""
from pathlib import Path
import json
import os
import resource
import shutil
import sqlite3
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build/retention-checks'
APP = ROOT / 'app/SiliconMeter.app'
DAY_MS = 86_400_000
TABLES = ('fast_samples', 'slow_samples', 'events', 'writer_batches')


def compile_fixture():
    BUILD.mkdir(parents=True, exist_ok=True)
    source = (ROOT / 'app/ComputeMonitor.swift').read_text().split('let app = NSApplication.shared')[0]
    (BUILD / 'main.swift').write_text(source + (ROOT / 'tests/retention_fixture.swift').read_text())
    subprocess.run(['swiftc', '-O', '-D', 'RETENTION_TEST', '-target', 'arm64-apple-macos13.0',
                    '-module-cache-path', str(ROOT / '.build/ModuleCache'), '-import-objc-header',
                    str(ROOT / 'app/TelemetryBackend.h'), str(BUILD / 'main.swift'),
                    str(ROOT / 'app/HistoryLogger.swift'), str(ROOT / 'app/Localization.swift'),
                    str(ROOT / '.build/TelemetryBackend.o'), str(ROOT / '.build/NetworkSampler.o'),
                    '-framework', 'AppKit', '-framework', 'IOKit', '-lsqlite3',
                    '-o', str(BUILD / 'fixture')], check=True, cwd=ROOT)


def run(mode, db, suite, now_ms=0, policy=0, kill_after=0, concurrent=False, timeout=120):
    env = os.environ.copy()
    env['CFFIXED_USER_HOME'] = str(db.parent.parent)
    env['HOME'] = str(db.parent.parent)
    args = [str(BUILD / 'fixture'), mode, str(db), suite]
    if mode == 'preferences':
        args.append(str(APP))
    elif mode != 'init':
        args += [str(now_ms), str(policy), str(kill_after), 'concurrent' if concurrent else 'none']
    return subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)


def check_db(db, full=False):
    with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
        assert con.execute('PRAGMA user_version').fetchone()[0] == 4
        pragma = 'PRAGMA integrity_check' if full else 'PRAGMA quick_check'
        assert con.execute(pragma).fetchone()[0] == 'ok'
        assert con.execute('PRAGMA foreign_key_check').fetchall() == []
        return {table: con.execute(f'SELECT count(*) FROM {table}').fetchone()[0] for table in TABLES}


def setup(db):
    db.parent.mkdir(parents=True, exist_ok=True)
    result = run('init', db, f'retention-test-{uuid.uuid4()}')
    assert result.returncode == 0, result.stderr
    check_db(db, full=True)


def seed(db, timestamps, old_run=False, referenced_run=False):
    """Copy real v4 row shapes, changing only keys and UTC timestamps."""
    with sqlite3.connect(db) as con:
        con.execute('PRAGMA foreign_keys=ON')
        run_id = con.execute('SELECT run_id FROM app_runs LIMIT 1').fetchone()[0]
        for table in ('fast_samples', 'slow_samples'):
            template = list(con.execute(f'SELECT * FROM {table} LIMIT 1').fetchone())
            columns = [row[1] for row in con.execute(f'PRAGMA table_info({table})')]
            for index, timestamp in enumerate(timestamps):
                values = template.copy()
                values[columns.index('seq')] = 1000 + index
                values[columns.index('utc_ms')] = timestamp
                con.execute(f'INSERT INTO {table} VALUES ({",".join("?" for _ in values)})', values)
        for index, timestamp in enumerate(timestamps):
            con.execute('INSERT INTO events (run_id,utc_ms,uptime_ms,kind,quality) VALUES (?,?,?,?,?)',
                        (run_id, timestamp, 0, f'retention_test_{index}', 'measured'))
            con.execute('INSERT INTO writer_batches VALUES (?,?,?,?,?,?,?)',
                        (run_id, 1000 + index, timestamp, 0.0, 1, 1, 1))
        if old_run:
            fields = [x[1] for x in con.execute('PRAGMA table_info(app_runs)')]
            row = list(con.execute('SELECT * FROM app_runs WHERE run_id=?', (run_id,)).fetchone())
            row[fields.index('run_id')] = 'retention-old-run'
            row[fields.index('start_utc_ms')] = min(timestamps) - 1000
            row[fields.index('end_utc_ms')] = min(timestamps) - 500
            con.execute(f'INSERT INTO app_runs VALUES ({",".join("?" for _ in row)})', row)
            old_timestamp = min(timestamps) - 1000
            for table in ('fast_samples', 'slow_samples'):
                columns = [x[1] for x in con.execute(f'PRAGMA table_info({table})')]
                template = list(con.execute(f'SELECT * FROM {table} WHERE run_id=? LIMIT 1', (run_id,)).fetchone())
                template[columns.index('run_id')] = 'retention-old-run'
                template[columns.index('seq')] = 1
                template[columns.index('utc_ms')] = old_timestamp
                con.execute(f'INSERT INTO {table} VALUES ({",".join("?" for _ in template)})', template)
            con.execute('INSERT INTO events (run_id,utc_ms,uptime_ms,kind,quality) VALUES (?,?,?,?,?)',
                        ('retention-old-run', old_timestamp, 0, 'old_run', 'measured'))
            con.execute('INSERT INTO writer_batches VALUES (?,?,?,?,?,?,?)',
                        ('retention-old-run', 1, old_timestamp, 0.0, 1, 1, 1))
        if referenced_run:
            con.execute('CREATE TABLE training_sessions (session_id TEXT PRIMARY KEY, start_run_id TEXT REFERENCES app_runs(run_id), end_run_id TEXT REFERENCES app_runs(run_id))')
            con.execute('INSERT INTO training_sessions VALUES (?,?,?)', ('legacy', 'retention-old-run', None))
    check_db(db, full=True)


def cleanup(db, now_ms, policy, concurrent=False, kill_after=0):
    result = run('cleanup', db, f'retention-cleanup-{uuid.uuid4()}', now_ms, policy,
                 kill_after=kill_after, concurrent=concurrent)
    if kill_after:
        marker = 'RETENTION_KILL_INSIDE_TRANSACTION' if kill_after < 0 else 'RETENTION_KILL_AFTER_BATCH'
        assert result.returncode == -9 and marker in result.stdout, (result.returncode, result.stderr)
        return None
    assert result.returncode == 0, (result.returncode, result.stderr)
    report = json.loads(result.stdout.strip().splitlines()[-1])
    assert report['completed'], report
    return report


def scenario(root, name, now_ms, days, timestamps, expected_deleted):
    db = root / name / 'telemetry.sqlite3'
    setup(db)
    seed(db, timestamps)
    report = cleanup(db, now_ms, days)
    check_db(db, full=True)
    for table in TABLES:
        assert report['deleted'].get(table, 0) == expected_deleted, (name, table, report)
    cutoff = now_ms - days * DAY_MS
    with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
        for table in TABLES:
            assert con.execute(f'SELECT count(*) FROM {table} WHERE utc_ms < ?', (cutoff,)).fetchone()[0] == 0
        retained = len(timestamps) - expected_deleted
        assert con.execute('SELECT count(*) FROM fast_samples WHERE seq>=1000').fetchone()[0] == retained
        assert con.execute('SELECT count(*) FROM slow_samples WHERE seq>=1000').fetchone()[0] == retained
        assert con.execute("SELECT count(*) FROM events WHERE kind GLOB 'retention_test_*'").fetchone()[0] == retained
        assert con.execute('SELECT count(*) FROM writer_batches WHERE batch_seq>=1000').fetchone()[0] == retained
    print(f'RETENTION_{name.upper()} PASS deleted={expected_deleted} per table')


def main():
    compile_fixture()
    now_ms = int(time.time() * 1000)
    with tempfile.TemporaryDirectory(prefix='siliconmeter-retention-') as temp:
        root = Path(temp)
        pref_dir = root / 'preferences'
        pref_dir.mkdir()
        result = run('preferences', pref_dir, f'retention-preferences-{uuid.uuid4()}')
        assert result.returncode == 0, result.stderr
        print(result.stdout.strip())

        one_cutoff = now_ms - DAY_MS
        scenario(root, 'one_day', now_ms, 1,
                 [now_ms - 2*DAY_MS, now_ms - DAY_MS - 3_600_000, one_cutoff - 1,
                  one_cutoff, one_cutoff + 1, now_ms - 23*3_600_000, now_ms], 3)
        seven_cutoff = now_ms - 7*DAY_MS
        scenario(root, 'seven_days', now_ms, 7,
                 [now_ms - 8*DAY_MS, seven_cutoff - 1, seven_cutoff, now_ms - 6*DAY_MS], 2)
        thirty_cutoff = now_ms - 30*DAY_MS
        scenario(root, 'thirty_days', now_ms, 30,
                 [now_ms - 31*DAY_MS, thirty_cutoff, now_ms - 29*DAY_MS], 1)

        db = root / 'forever' / 'telemetry.sqlite3'
        setup(db)
        seed(db, [now_ms - 100*DAY_MS])
        before = check_db(db)
        report = cleanup(db, now_ms, 0)
        assert check_db(db, full=True)['fast_samples'] == before['fast_samples'] + 1
        assert all(report['deleted'].get(t, 0) == 0 for t in TABLES)
        print('RETENTION_FOREVER PASS no age deletion')

        db = root / 'referenced' / 'telemetry.sqlite3'
        setup(db)
        seed(db, [now_ms - 50*DAY_MS], old_run=True, referenced_run=True)
        cleanup(db, now_ms, 1)
        with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
            assert con.execute("SELECT count(*) FROM app_runs WHERE run_id='retention-old-run'").fetchone()[0] == 1
            assert con.execute('PRAGMA foreign_key_check').fetchall() == []
        print('RETENTION_REFERENCES PASS old run retained for legacy FK')

        db = root / 'recently_ended_run' / 'telemetry.sqlite3'
        setup(db)
        seed(db, [now_ms - 50*DAY_MS], old_run=True)
        with sqlite3.connect(db) as con:
            con.execute("UPDATE app_runs SET end_utc_ms=? WHERE run_id='retention-old-run'", (now_ms,))
        cleanup(db, now_ms, 1)
        check_db(db, full=True)
        with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
            assert con.execute("SELECT count(*) FROM app_runs WHERE run_id='retention-old-run'").fetchone()[0] == 1
            assert con.execute("SELECT count(*) FROM fast_samples WHERE run_id='retention-old-run'").fetchone()[0] == 0
        print('RETENTION_RECENT_RUN PASS recent end metadata retained / old children deleted')

        db = root / 'rollback' / 'telemetry.sqlite3'
        setup(db)
        old = now_ms - 60*DAY_MS
        seed(db, [old + i for i in range(6_000)])
        cleanup(db, now_ms, 1, kill_after=-100)
        check_db(db, full=True)
        with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
            assert con.execute('SELECT count(*) FROM fast_samples WHERE utc_ms<?', (now_ms-DAY_MS,)).fetchone()[0] == 6_000
        cleanup(db, now_ms, 1)
        check_db(db, full=True)
        with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
            assert con.execute('SELECT count(*) FROM fast_samples WHERE utc_ms<?', (now_ms-DAY_MS,)).fetchone()[0] == 0
        print('RETENTION_ROLLBACK PASS kill inside transaction / rollback / retry / integrity')

        # Crash after two committed 5k-row batches; restart finishes the rest.
        db = root / 'crash' / 'telemetry.sqlite3'
        setup(db)
        old = now_ms - 60*DAY_MS
        seed(db, [old + i for i in range(20_000)], old_run=True)
        before = check_db(db)
        cleanup(db, now_ms, 1, kill_after=2)
        middle = check_db(db, full=True)
        assert 0 < before['fast_samples'] - middle['fast_samples'] < 20_000
        report = cleanup(db, now_ms, 1, concurrent=True)
        after = check_db(db, full=True)
        assert after['fast_samples'] >= 2 and after['slow_samples'] >= 2
        with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
            assert con.execute('SELECT count(*) FROM fast_samples WHERE utc_ms<?', (now_ms-DAY_MS,)).fetchone()[0] == 0
            assert con.execute("SELECT count(*) FROM app_runs WHERE run_id='retention-old-run'").fetchone()[0] == 0
        print('RETENTION_CRASH PASS committed batches / restart / new samples / FK / integrity')

        # Larger one-time cleanup and bounded transaction/report metrics.
        db = root / 'large' / 'telemetry.sqlite3'
        setup(db)
        seed(db, [old + i for i in range(40_000)])
        cpu_before = resource.getrusage(resource.RUSAGE_CHILDREN)
        started = time.monotonic()
        report = cleanup(db, now_ms, 1, concurrent=True)
        elapsed = time.monotonic() - started
        cpu_after = resource.getrusage(resource.RUSAGE_CHILDREN)
        after = check_db(db, full=True)
        assert report['deleted'].get('fast_samples') == 40_000
        assert after['fast_samples'] >= 2  # new current-run rows survive
        assert report['transactions'] >= 8 and report['scanned_batches'] >= 8
        assert report['main_heartbeat_count'] >= 20
        assert report['max_main_heartbeat_gap_ms'] < 250
        with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
            freelist = con.execute('PRAGMA freelist_count').fetchone()[0]
            assert con.execute("SELECT count(*) FROM events WHERE kind='thermal_change' AND utc_ms>=?", (now_ms,)).fetchone()[0] == 1
            assert con.execute('SELECT count(*) FROM app_runs WHERE end_utc_ms IS NOT NULL').fetchone()[0] >= 2
        print('RETENTION_LARGE PASS', json.dumps({
            'deleted': report['deleted'], 'transactions': report['transactions'],
            'scanned_batches': report['scanned_batches'], 'elapsed_s': round(elapsed, 3),
            'max_transaction_ms': round(report['max_transaction_ms'], 3),
            'main_heartbeat_count': report['main_heartbeat_count'],
            'max_main_heartbeat_gap_ms': round(report['max_main_heartbeat_gap_ms'], 3),
            'child_cpu_s': round((cpu_after.ru_utime+cpu_after.ru_stime)-(cpu_before.ru_utime+cpu_before.ru_stime), 3),
            'fixture_peak_rss_mib': round(report['fixture_peak_rss_bytes']/(1024*1024), 2),
            'db_bytes': db.stat().st_size,
            'wal_bytes_before_stop': report['wal_bytes_before_stop'],
            'wal_bytes': db.with_name(db.name+'-wal').stat().st_size if db.with_name(db.name+'-wal').exists() else 0,
            'freelist_pages': freelist}, sort_keys=True))


if __name__ == '__main__':
    main()
