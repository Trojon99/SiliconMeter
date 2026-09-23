#!/usr/bin/env python3
"""Exercise the production logger against genuine v1, backed-up v2 and v3 copies."""
from pathlib import Path
import json
import shutil
import sqlite3
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BACKUPS = sorted((ROOT / 'backups').glob('pre-v3-*/consistent-telemetry.sqlite3'))
assert BACKUPS, 'a pre-v3 SQLite backup is required'
V2_BACKUP = BACKUPS[-1]
V3_BACKUPS = sorted((ROOT / 'backups').glob('pre-v4-*/consistent-telemetry.sqlite3'))
assert V3_BACKUPS, 'a pre-v4 SQLite backup is required'
V3_BACKUP = V3_BACKUPS[-1]
BUILD = ROOT / '.build/migration-checks'
BUILD.mkdir(parents=True, exist_ok=True)

def git_file(name):
    return subprocess.check_output(['git', 'show', f'78e2fb2:{name}'], cwd=ROOT, text=True)

old_source = git_file('app/ComputeMonitor.swift').split('let app = NSApplication.shared')[0]
(BUILD / 'main.swift').write_text(old_source + (ROOT / 'tests/history_fixture.swift').read_text())
(BUILD / 'HistoryLogger-v1.swift').write_text(git_file('app/HistoryLogger.swift'))
common = ['swiftc', '-O', '-target', 'arm64-apple-macos13.0', '-module-cache-path', str(ROOT / '.build/ModuleCache'),
          '-import-objc-header', str(ROOT / 'app/TelemetryBackend.h')]
subprocess.run(common + [str(BUILD / 'main.swift'), str(BUILD / 'HistoryLogger-v1.swift'),
                         str(ROOT / '.build/TelemetryBackend.o'), str(ROOT / '.build/NetworkSampler.o'), '-framework', 'AppKit', '-framework', 'IOKit',
                         '-lsqlite3', '-o', str(BUILD / 'v1-fixture')], check=True, cwd=ROOT)
current = ROOT / '.build/history-checks/fixture'
assert current.exists(), 'run tests/run-history-checks.py first'

TABLES = ('app_runs', 'fast_samples', 'slow_samples', 'events', 'writer_batches')
def snapshot(path):
    with sqlite3.connect(path) as c:
        return {name: c.execute(f'SELECT * FROM {name}').fetchall() for name in TABLES}

def schema(path):
    with sqlite3.connect(path) as c:
        return {(kind, name): sql for kind, name, sql in
                c.execute("SELECT type,name,sql FROM sqlite_master WHERE type IN ('table','index','trigger') AND name NOT LIKE 'sqlite_%'")}

def check(path, before, legacy):
    with sqlite3.connect(path) as c:
        assert c.execute('PRAGMA user_version').fetchone()[0] == 4
        assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        for name in TABLES:
            after = c.execute(f'SELECT * FROM {name}').fetchall()
            assert all(any(new[:len(row)] == row for new in after) for row in before[name]), f'{name} lost rows'
        assert (c.execute("SELECT count(*) FROM sqlite_master WHERE name='training_sessions'").fetchone()[0] == 1) == legacy
        assert len(c.execute('SELECT * FROM fast_samples').fetchall()) > len(before['fast_samples'])
        assert c.execute("SELECT count(*) FROM fast_samples WHERE network_rx_bytes_per_sec IS NULL AND network_rx_bytes_per_sec_quality='unavailable'").fetchone()[0] >= len(before['fast_samples'])

with tempfile.TemporaryDirectory(prefix='minimal-migrations-') as tmp:
    temp = Path(tmp)
    v1 = temp / 'v1.sqlite3'
    subprocess.run([str(BUILD / 'v1-fixture'), str(v1), 'normal'], check=True)
    with sqlite3.connect(v1) as c:
        assert c.execute('PRAGMA user_version').fetchone()[0] == 1
    v1_schema = schema(v1)
    wrong_columns = temp / 'wrong-columns.sqlite3'
    shutil.copy2(v1, wrong_columns)
    with sqlite3.connect(wrong_columns) as c:
        c.execute('ALTER TABLE events ADD COLUMN unexpected TEXT')
    result = subprocess.run([str(current), str(wrong_columns), 'resume'], capture_output=True, text=True)
    assert 'History schema or integrity check failed' in result.stderr
    with sqlite3.connect(wrong_columns) as c:
        assert c.execute('PRAGMA user_version').fetchone()[0] == 1
        assert 'unexpected' in [r[1] for r in c.execute('PRAGMA table_info(events)')]
    before = snapshot(v1)
    subprocess.run([str(current), str(v1), 'resume'], check=True)
    check(v1, before, False)

    v2 = temp / 'v2.sqlite3'
    with sqlite3.connect(f'file:{V2_BACKUP}?mode=ro', uri=True) as source, sqlite3.connect(v2) as target:
        source.backup(target)
    with sqlite3.connect(v2) as c:
        assert c.execute('PRAGMA user_version').fetchone()[0] == 2
        legacy_rows = c.execute('SELECT * FROM training_sessions').fetchall()
    v2_schema = schema(v2)
    assert all(v2_schema.get(key) == ddl for key, ddl in v1_schema.items()), 'v2 changed core telemetry schema'
    assert set(v2_schema) - set(v1_schema) == {
        ('table','training_sessions'), ('index','one_active_training_session'),
        ('index','training_sessions_recent')}, 'unexpected v2 schema change'
    before = snapshot(v2)
    subprocess.run([str(current), str(v2), 'resume'], check=True)
    check(v2, before, True)
    with sqlite3.connect(v2) as c:
        assert c.execute('SELECT * FROM training_sessions').fetchall() == legacy_rows

    v3 = temp / 'v3.sqlite3'
    with sqlite3.connect(f'file:{V3_BACKUP}?mode=ro', uri=True) as source, sqlite3.connect(v3) as target:
        source.backup(target)
    with sqlite3.connect(v3) as c:
        assert c.execute('PRAGMA user_version').fetchone()[0] == 3
        v3_legacy_rows = c.execute('SELECT * FROM training_sessions').fetchall()
    before = snapshot(v3)
    subprocess.run([str(current), str(v3), 'resume'], check=True)
    check(v3, before, True)
    with sqlite3.connect(v3) as c:
        assert c.execute('SELECT * FROM training_sessions').fetchall() == v3_legacy_rows

    future = temp / 'future.sqlite3'
    with sqlite3.connect(v3) as source, sqlite3.connect(future) as target:
        source.backup(target)
    with sqlite3.connect(future) as c:
        c.execute('PRAGMA user_version=5')
    result = subprocess.run([str(current), str(future), 'resume'], capture_output=True, text=True)
    assert 'History schema or integrity check failed' in result.stderr
    with sqlite3.connect(future) as c:
        assert c.execute('PRAGMA user_version').fetchone()[0] == 5
        assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'

    broken = temp / 'broken.sqlite3'
    shutil.copy2(v1, broken)
    with sqlite3.connect(broken) as c:
        c.execute('DROP TABLE writer_batches')
        c.execute('PRAGMA user_version=1')
    result = subprocess.run([str(current), str(broken), 'resume'], capture_output=True, text=True)
    assert 'History schema or integrity check failed' in result.stderr
    with sqlite3.connect(broken) as c:
        assert c.execute('PRAGMA user_version').fetchone()[0] == 1
        assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    print(json.dumps({'v1_to_v4': 'PASS', 'v2_to_v4': 'PASS', 'v3_to_v4': 'PASS', 'invalid_schema': 'REJECTED',
                      'wrong_columns': 'REJECTED', 'future_version': 'REJECTED',
                      'core_ddl_identical': True, 'v2_legacy_rows_preserved': len(legacy_rows)}))
