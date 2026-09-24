#!/usr/bin/env python3
"""Compare ordinary pre-retention and retention builds in separate test homes."""
from pathlib import Path
import atexit
import ctypes
import datetime
import hashlib
import json
import os
import plistlib
import shutil
import signal
import sqlite3
import statistics
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
BASE = '820a89f'  # identity-migration commit immediately before Step 4.2
CURRENT = ROOT / 'app/SiliconMeter.app'


def remove_test_domain(domain):
    subprocess.run(['defaults', 'delete', domain], capture_output=True)
    plist = Path.home() / 'Library/Preferences' / f'{domain}.plist'
    if plist.exists() and plistlib.loads(plist.read_bytes()) == {}:
        plist.unlink()


class TaskInfo(ctypes.Structure):
    _fields_ = [(key, ctypes.c_uint64) for key in
                ('virtual_size', 'resident_size', 'total_user', 'total_system', 'threads_user', 'threads_system')] + [
                    (key, ctypes.c_int32) for key in ('policy', 'faults', 'pageins', 'cow_faults',
                    'messages_sent', 'messages_received', 'syscalls_mach', 'syscalls_unix', 'csw',
                    'threadnum', 'numrunning', 'priority')]


class Timebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]


def baseline_app():
    build = ROOT / '.build/retention-baseline'
    app = build / 'SiliconMeter.app'
    src = build / 'src'
    src.mkdir(parents=True, exist_ok=True)
    (app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    for name in ('ComputeMonitor.swift', 'HistoryLogger.swift', 'Localization.swift', 'IdentityMigration.swift'):
        value = subprocess.check_output(['git', 'show', f'{BASE}:app/{name}'], cwd=ROOT)
        (src / ('main.swift' if name == 'ComputeMonitor.swift' else name)).write_bytes(value)
    cmd = ['swiftc', '-O', '-target', 'arm64-apple-macos13.0', '-module-cache-path',
           str(ROOT / '.build/ModuleCache'), '-import-objc-header', str(ROOT / 'app/TelemetryBackend.h'),
           str(src / 'main.swift'), str(src / 'HistoryLogger.swift'), str(src / 'Localization.swift'),
           str(src / 'IdentityMigration.swift'), str(ROOT / '.build/TelemetryBackend.o'),
           str(ROOT / '.build/NetworkSampler.o'), '-framework', 'AppKit', '-framework', 'IOKit',
           '-lsqlite3', '-o', str(app / 'Contents/MacOS/SiliconMeter')]
    subprocess.run(cmd, check=True, cwd=ROOT)
    shutil.copy2(ROOT / 'app/Info.plist', app / 'Contents/Info.plist')
    for language in ('en.lproj', 'zh-Hans.lproj'):
        shutil.copytree(ROOT / 'app' / language, app / 'Contents/Resources' / language, dirs_exist_ok=True)
    return app


def isolated_app(source, root, name):
    app = root / f'{name}.app'
    shutil.copytree(source, app)
    info = app / 'Contents/Info.plist'
    plist = plistlib.loads(info.read_bytes())
    domain = f'io.github.trojon99.siliconmeter.steadytest.{uuid.uuid4().hex}'
    plist['CFBundleIdentifier'] = domain
    info.write_bytes(plistlib.dumps(plist))
    atexit.register(remove_test_domain, domain)
    return app / 'Contents/MacOS/SiliconMeter'


def db_metrics(db, since_ms):
    with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
        assert con.execute('PRAGMA quick_check').fetchone()[0] == 'ok'
        fast = [r[0] for r in con.execute('SELECT utc_ms FROM fast_samples WHERE utc_ms>=? ORDER BY utc_ms', (since_ms,))]
        slow = [r[0] for r in con.execute('SELECT utc_ms FROM slow_samples WHERE utc_ms>=? ORDER BY utc_ms', (since_ms,))]
        flush_count = con.execute('SELECT count(*) FROM writer_batches WHERE utc_ms>=?', (since_ms,)).fetchone()[0]
        gaps = [b-a for a, b in zip(fast, fast[1:])]
        return {'fast_rows': len(fast), 'slow_rows': len(slow), 'fast_gap_median_ms': statistics.median(gaps) if gaps else None,
                'flush_count': flush_count}


def measure(binary, root, lib, ticks_per_second, duration=65, warmup=25):
    home = root / 'home'
    home.mkdir(parents=True)
    env = os.environ.copy()
    env['CFFIXED_USER_HOME'] = str(home)
    env['HOME'] = str(home)
    rows = []
    app = subprocess.Popen([str(binary)], cwd=ROOT, env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    start = time.monotonic()
    start_utc_ms = int(time.time() * 1000)
    try:
        while time.monotonic() - start < duration:
            assert app.poll() is None, 'App exited early'
            info = TaskInfo()
            rc = lib.proc_pidinfo(app.pid, 4, 0, ctypes.byref(info), ctypes.sizeof(info))
            assert rc == ctypes.sizeof(info), 'PROC_PIDTASKINFO failed'
            rows.append({'elapsed_s': time.monotonic()-start, 'rss_bytes': info.resident_size,
                         'cpu_s': (info.total_user+info.total_system)/ticks_per_second,
                         'threads': info.threadnum})
            time.sleep(2)
    finally:
        if app.poll() is None:
            app.send_signal(signal.SIGTERM)
            app.wait(timeout=10)
    stable = [r for r in rows if r['elapsed_s'] >= warmup]
    assert len(stable) >= 10
    seconds = stable[-1]['elapsed_s'] - stable[0]['elapsed_s']
    cpu = stable[-1]['cpu_s'] - stable[0]['cpu_s']
    db = home / 'Library/Application Support/SiliconMeter/telemetry.sqlite3'
    db_values = db_metrics(db, start_utc_ms + warmup*1000)
    return {'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
            'warmup_s': warmup, 'stable_duration_s': seconds,
            'cpu_s': cpu, 'cpu_percent_one_core': cpu/seconds*100,
            'rss_first_mib': stable[0]['rss_bytes']/1048576,
            'rss_last_mib': stable[-1]['rss_bytes']/1048576,
            'rss_max_mib': max(r['rss_bytes'] for r in stable)/1048576,
            'threads_median': statistics.median(r['threads'] for r in stable),
            'db': db_values}


def main():
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    assert not output.exists(), 'refusing to overwrite measurement'
    system = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    timebase = Timebase()
    assert system.mach_timebase_info(ctypes.byref(timebase)) == 0 and timebase.denom
    ticks_per_second = 1e9*timebase.denom/timebase.numer
    lib = ctypes.CDLL('/usr/lib/libproc.dylib')
    lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
    lib.proc_pidinfo.restype = ctypes.c_int
    baseline = baseline_app()
    with tempfile.TemporaryDirectory(prefix='siliconmeter-steady-') as temp:
        root = Path(temp)
        old = isolated_app(baseline, root, 'before')
        new = isolated_app(CURRENT, root, 'after')
        before = measure(old, root / 'before', lib, ticks_per_second)
        print('RETENTION_STEADY before', json.dumps(before, sort_keys=True), flush=True)
        after = measure(new, root / 'after', lib, ticks_per_second)
        print('RETENTION_STEADY after', json.dumps(after, sort_keys=True), flush=True)
    record = {'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'baseline_revision': BASE, 'method': 'ordinary optimized AppKit binaries, unique test bundle IDs and homes, external libproc every 2 seconds; consecutive 65-second runs with 25-second warmup; fast-sample gap is cadence, not collector latency',
              'before': before, 'after': after,
              'cpu_percent_point_delta': after['cpu_percent_one_core']-before['cpu_percent_one_core'],
              'rss_last_mib_delta': after['rss_last_mib']-before['rss_last_mib']}
    output.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    print('RETENTION_STEADY saved', output)


if __name__ == '__main__':
    main()
