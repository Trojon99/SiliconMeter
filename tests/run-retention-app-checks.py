#!/usr/bin/env python3
"""Run the real AppKit app against isolated fresh and pre-retention v4 homes."""
from pathlib import Path
import atexit
import importlib.util
import os
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('retention_checks', ROOT / 'tests/run-retention-checks.py')
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)
compile_fixture, setup, seed, check_db = checks.compile_fixture, checks.setup, checks.seed, checks.check_db
SMOKE_APP = ROOT / '.build/SiliconMeterSmoke.app'
FIXTURE = ROOT / '.build/retention-checks/fixture'
DAY_MS = 86_400_000


def remove_test_domain(domain):
    subprocess.run(['defaults', 'delete', domain], capture_output=True)
    plist = Path.home() / 'Library/Preferences' / f'{domain}.plist'
    if plist.exists() and plistlib.loads(plist.read_bytes()) == {}:
        plist.unlink()


def test_app(root, name):
    app = root / f'{name}.app'
    shutil.copytree(SMOKE_APP, app)
    info = app / 'Contents/Info.plist'
    plist = plistlib.loads(info.read_bytes())
    domain = f'io.github.trojon99.siliconmeter.retentiontest.{uuid.uuid4().hex}'
    plist['CFBundleIdentifier'] = domain
    info.write_bytes(plistlib.dumps(plist))
    atexit.register(remove_test_domain, domain)
    return app / 'Contents/MacOS/SiliconMeter', domain


def launch(home, app, expected):
    env = os.environ.copy()
    env['CFFIXED_USER_HOME'] = str(home)
    env['HOME'] = str(home)
    result = subprocess.run([str(app)], env=env, cwd=ROOT, capture_output=True,
                            text=True, timeout=30)
    assert result.returncode == 0, (result.returncode, result.stderr[-1000:])
    assert 'result=PASS' in result.stdout and f'retention={expected}' in result.stdout, result.stdout
    return env


def choose(home, db, domain, from_days, to_days, accept):
    env = os.environ.copy()
    env['CFFIXED_USER_HOME'] = str(home)
    env['HOME'] = str(home)
    result = subprocess.run([str(FIXTURE), 'choose', str(db), domain,
                             str(from_days), str(to_days), 'accept' if accept else 'cancel'],
                            env=env, cwd=ROOT, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, (result.returncode, result.stderr)


def old_count(db, cutoff):
    with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
        return con.execute('SELECT count(*) FROM events WHERE kind LIKE \'retention_test_%\' AND utc_ms<?',
                           (cutoff,)).fetchone()[0]


def main():
    assert SMOKE_APP.exists(), 'run sh app/ui-smoke.sh --build-only first'
    compile_fixture()
    now_ms = int(time.time() * 1000)
    with tempfile.TemporaryDirectory(prefix='siliconmeter-retention-app-') as temp:
        root = Path(temp)
        fresh = root / 'fresh'
        fresh.mkdir()
        fresh_app, _ = test_app(root, 'fresh-smoke')
        launch(fresh, fresh_app, 30)
        fresh_db = fresh / 'Library/Application Support/SiliconMeter/telemetry.sqlite3'
        check_db(fresh_db, full=True)
        launch(fresh, fresh_app, 30)
        print('RETENTION_APP_FRESH PASS 30 Days / bilingual UI / relaunch')

        existing = root / 'existing'
        existing.mkdir()
        existing_app, existing_domain = test_app(root, 'existing-smoke')
        db = existing / 'Library/Application Support/SiliconMeter/telemetry.sqlite3'
        setup(db)
        seed(db, [now_ms - 100 * DAY_MS])
        cutoff = now_ms - 30 * DAY_MS
        assert old_count(db, cutoff) == 1
        launch(existing, existing_app, 0)
        assert old_count(db, cutoff) == 1
        launch(existing, existing_app, 0)
        assert old_count(db, cutoff) == 1
        check_db(db, full=True)
        print('RETENTION_APP_EXISTING PASS Forever / no first-launch deletion / relaunch')

        migrated = root / 'legacy-path'
        migrated.mkdir()
        migrated_app, _ = test_app(root, 'legacy-smoke')
        legacy_db = migrated / 'Library/Application Support/Compute Monitor/telemetry.sqlite3'
        setup(legacy_db)
        seed(legacy_db, [now_ms - 100 * DAY_MS])
        launch(migrated, migrated_app, 0)
        migrated_db = migrated / 'Library/Application Support/SiliconMeter/telemetry.sqlite3'
        assert not legacy_db.exists() and old_count(migrated_db, cutoff) == 1
        check_db(migrated_db, full=True)
        print('RETENTION_APP_MIGRATED PASS legacy directory move / Forever / old row preserved')

        choose(existing, db, existing_domain, 0, 30, False)
        launch(existing, existing_app, 0)
        assert old_count(db, cutoff) == 1
        choose(existing, db, existing_domain, 0, 30, True)
        launch(existing, existing_app, 30)
        assert old_count(db, cutoff) == 0
        check_db(db, full=True)
        print('RETENTION_APP_CHOICE PASS cancel preserves / confirmed 30 Days cleans / relaunch')


if __name__ == '__main__':
    main()
