#!/usr/bin/env python3
"""Isolated A/B/C/D identity migration checks using the real v4 database structure."""
from pathlib import Path
import hashlib
import os
import plistlib
import sqlite3
import subprocess
import tempfile
import shutil

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / '.build/SiliconMeterSmoke.app/Contents/MacOS/SiliconMeter'
LEGACY_SOURCE = Path.home() / 'Library/Application Support/Compute Monitor/telemetry.sqlite3'
CANONICAL_SOURCE = Path.home() / 'Library/Application Support/SiliconMeter/telemetry.sqlite3'
SOURCE = LEGACY_SOURCE if LEGACY_SOURCE.exists() else CANONICAL_SOURCE
TABLES = ('app_runs', 'fast_samples', 'slow_samples', 'events')


def check_db(db):
    with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
        assert con.execute('PRAGMA user_version').fetchone()[0] == 4
        assert con.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        columns = {row[1] for row in con.execute('PRAGMA table_info(fast_samples)')}
        assert {'network_rx_bytes_per_sec', 'network_tx_bytes_per_sec'} <= columns
        return {table: con.execute(f'SELECT count(*) FROM {table}').fetchone()[0] for table in TABLES}


def seed(db, marker):
    db.parent.mkdir(parents=True)
    with sqlite3.connect(f'file:{SOURCE}?mode=ro', uri=True) as source, sqlite3.connect(db) as target:
        source.backup(target)
    # Leave one committed event in WAL, as can happen after an abnormal stop.
    script = '''import os, sqlite3, sys, time
c=sqlite3.connect(sys.argv[1]); c.execute('PRAGMA journal_mode=WAL'); c.execute('PRAGMA wal_autocheckpoint=0')
run=c.execute('SELECT run_id FROM app_runs LIMIT 1').fetchone()[0]
c.execute('INSERT INTO events (run_id,utc_ms,uptime_ms,kind,old_value,new_value,quality) VALUES (?,?,?,?,?,?,?)',
          (run,int(time.time()*1000),0,'identity_migration_fixture',None,sys.argv[2],'measured'))
c.commit(); os._exit(0)
'''
    subprocess.run(['python3', '-c', script, str(db), marker], check=True)
    assert db.with_name(db.name + '-wal').exists()
    assert db.with_name(db.name + '-shm').exists()
    (db.parent / 'logger-metadata.txt').write_text(marker)
    return check_db(db)


def digest_tree(directory):
    return {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in directory.rglob('*') if p.is_file()}


def launch(home):
    env = os.environ.copy()
    env['CFFIXED_USER_HOME'] = str(home)
    env['HOME'] = str(home)
    result = subprocess.run([str(APP)], cwd=ROOT, env=env, capture_output=True, text=True, timeout=25)
    assert result.returncode == 0, (result.returncode, result.stderr[-800:])
    assert 'UI_SMOKE' in result.stdout and 'result=PASS' in result.stdout, (result.stdout, result.stderr[-800:])
    assert 'accessory=true' in result.stdout, result.stdout


def run():
    assert APP.exists(), 'run sh app/ui-smoke.sh --build-only first'
    assert SOURCE.exists(), 'real v4 source database needed for a structural copy'
    info = plistlib.loads((ROOT / 'app/SiliconMeter.app/Contents/Info.plist').read_bytes())
    assert info['LSUIElement'] is True
    assert info['CFBundleIdentifier'] == 'io.github.trojon99.siliconmeter'
    with tempfile.TemporaryDirectory(prefix='siliconmeter-identity-') as temp:
        root = Path(temp)
        # D. Test the allowlist and new-value precedence in isolated domains.
        fixture_build = ROOT / '.build/identity-migration'
        fixture_build.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'tests/identity_migration_fixture.swift', fixture_build / 'main.swift')
        fixture = fixture_build / 'fixture'
        subprocess.run(['swiftc', '-O', '-target', 'arm64-apple-macos13.0',
                        '-module-cache-path', str(ROOT / '.build/ModuleCache'),
                        str(fixture_build / 'main.swift'), str(ROOT / 'app/IdentityMigration.swift'),
                        '-o', str(fixture)], check=True, cwd=ROOT)
        fixture_home = root / 'preference-fixture'
        fixture_home.mkdir()
        fixture_env = os.environ.copy()
        fixture_env['CFFIXED_USER_HOME'] = str(fixture_home)
        fixture_env['HOME'] = str(fixture_home)
        result = subprocess.run([str(fixture), str(root / 'directory-fixture')],
                                env=fixture_env, capture_output=True, text=True, timeout=15)
        assert result.returncode == 0 and 'IDENTITY_MIGRATION_FIXTURE PASS' in result.stdout, result.stderr
        print('IDENTITY_D PASS language / all five primary metrics / new values win')

        # A. No legacy data. The app makes a new canonical v4 database.
        fresh = root / 'fresh'
        fresh.mkdir()
        launch(fresh)
        fresh_db = fresh / 'Library/Application Support/SiliconMeter/telemetry.sqlite3'
        assert check_db(fresh_db)['app_runs'] == 1
        assert not (fresh / 'Library/Application Support/Compute Monitor').exists()
        print('IDENTITY_A PASS fresh install / SQLite v4 / UI languages / accessory')

        # B. A real-structure v4 copy with committed WAL and another file.
        home = root / 'legacy'
        old = home / 'Library/Application Support/Compute Monitor'
        new = home / 'Library/Application Support/SiliconMeter'
        before = seed(old / 'telemetry.sqlite3', 'legacy')
        launch(home)
        assert not old.exists() and new.is_dir()
        assert (new / 'logger-metadata.txt').read_text() == 'legacy'
        after = check_db(new / 'telemetry.sqlite3')
        assert after['app_runs'] == before['app_runs'] + 1
        assert after['fast_samples'] > before['fast_samples']
        assert after['slow_samples'] > before['slow_samples']
        assert after['events'] > before['events']
        launch(home)
        assert not old.exists()
        assert check_db(new / 'telemetry.sqlite3')['app_runs'] == after['app_runs'] + 1
        print('IDENTITY_B PASS whole-directory WAL migration / rows / append / second launch')

        # C. Existing canonical history wins; legacy bytes remain untouched.
        home = root / 'conflict'
        old = home / 'Library/Application Support/Compute Monitor'
        new = home / 'Library/Application Support/SiliconMeter'
        old_before = seed(old / 'telemetry.sqlite3', 'legacy-conflict')
        new_before = seed(new / 'telemetry.sqlite3', 'canonical-conflict')
        old_hashes = digest_tree(old)
        launch(home)
        assert old.exists() and digest_tree(old) == old_hashes
        assert check_db(old / 'telemetry.sqlite3') == old_before
        current_after = check_db(new / 'telemetry.sqlite3')
        assert current_after['app_runs'] == new_before['app_runs'] + 1
        assert current_after['fast_samples'] > new_before['fast_samples']
        assert (old / 'logger-metadata.txt').read_text() == 'legacy-conflict'
        assert (new / 'logger-metadata.txt').read_text() == 'canonical-conflict'
        print('IDENTITY_C PASS conflict preserves legacy / uses canonical / both SQLite intact')


if __name__ == '__main__':
    run()
