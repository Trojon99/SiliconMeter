#!/usr/bin/env python3
"""Compare the same ordinary app with native network sampling disabled/enabled."""
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'app/SiliconMeter.app/Contents/MacOS/SiliconMeter'
DB = Path.home() / 'Library/Application Support/SiliconMeter/telemetry.sqlite3'
OUT = ROOT / 'docs/results/network-ab.json'

class TaskInfo(ctypes.Structure):
    _fields_ = [(key, ctypes.c_uint64) for key in
                ('virtual_size', 'resident_size', 'total_user', 'total_system', 'threads_user', 'threads_system')] + [
                    (key, ctypes.c_int32) for key in ('policy', 'faults', 'pageins', 'cow_faults',
                    'messages_sent', 'messages_received', 'syscalls_mach', 'syscalls_unix', 'csw',
                    'threadnum', 'numrunning', 'priority')]

class Timebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]

system = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
lib = ctypes.CDLL('/usr/lib/libproc.dylib')
lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
lib.proc_pidinfo.restype = ctypes.c_int
timebase = Timebase()
assert system.mach_timebase_info(ctypes.byref(timebase)) == 0 and timebase.denom
seconds_per_tick = timebase.numer / timebase.denom / 1e9

def read_task(pid):
    info = TaskInfo()
    assert lib.proc_pidinfo(pid, 4, 0, ctypes.byref(info), ctypes.sizeof(info)) == ctypes.sizeof(info)
    return {'cpu_s': (info.total_user + info.total_system) * seconds_per_tick,
            'rss_mb': info.resident_size / 1048576, 'threads': info.threadnum,
            'context_switches': info.csw}

def db_query(sql, args=()):
    with sqlite3.connect(f'file:{DB}?mode=ro', uri=True, timeout=10) as c:
        return c.execute(sql, args).fetchall()

def run(label, seconds, disabled):
    env = os.environ.copy()
    env.pop('COMPUTE_MONITOR_NETWORK_DISABLED', None)
    if disabled: env['COMPUTE_MONITOR_NETWORK_DISABLED'] = '1'
    old_runs = {r[0] for r in db_query('SELECT run_id FROM app_runs')}
    app = subprocess.Popen([str(APP)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    start = time.monotonic()
    observations = []
    try:
        while True:
            elapsed = time.monotonic() - start
            assert app.poll() is None, f'{label} exited early'
            observations.append({'elapsed_s': round(elapsed, 2), **read_task(app.pid)})
            if elapsed >= seconds: break
            time.sleep(min(30, seconds-elapsed))
    finally:
        if app.poll() is None:
            subprocess.run(['osascript', '-e', 'tell application id "io.github.trojon99.siliconmeter" to quit'],
                           check=True, timeout=20, stdout=subprocess.DEVNULL)
            app.wait(timeout=20)
    new_runs = db_query('SELECT run_id FROM app_runs')
    run_ids = [r[0] for r in new_runs if r[0] not in old_runs]
    assert len(run_ids) == 1, (label, run_ids)
    run_id = run_ids[0]
    fast = db_query('SELECT utc_ms,network_rx_bytes_per_sec_quality,network_tx_bytes_per_sec_quality,'
                    'network_rx_bytes_per_sec,network_tx_bytes_per_sec,network_rx_bytes_per_sec_window_s '
                    'FROM fast_samples WHERE run_id=? ORDER BY seq', (run_id,))
    assert fast
    gaps = [(fast[i][0]-fast[i-1][0])/1000 for i in range(1,len(fast))]
    steady = [r for r in observations if r['elapsed_s'] >= 60]
    assert len(steady) >= 2
    cpu_s = steady[-1]['cpu_s']-steady[0]['cpu_s']
    steady_s = steady[-1]['elapsed_s']-steady[0]['elapsed_s']
    qualities = {q:sum(row[1]==q and row[2]==q for row in fast) for q in ('measured','estimated','unavailable','invalid','stale')}
    assert sum(qualities.values()) == len(fast)
    summary = {'label':label,'network_enabled':not disabled,'pid':app.pid,'duration_s':round(observations[-1]['elapsed_s'],2),
               'run_id':run_id,'exit_code':app.returncode,'cpu_s_after_warmup':round(cpu_s,3),
               'cpu_percent_one_core_after_warmup':round(100*cpu_s/steady_s,3),
               'rss_mb':{'initial':round(observations[0]['rss_mb'],2),'final':round(observations[-1]['rss_mb'],2),
                         'late_range':round(max(r['rss_mb'] for r in steady)-min(r['rss_mb'] for r in steady),2)},
               'threads_final':observations[-1]['threads'],
               'context_switches_after_warmup':steady[-1]['context_switches']-steady[0]['context_switches'],
               'fast_rows':len(fast),'slow_rows':db_query('SELECT count(*) FROM slow_samples WHERE run_id=?',(run_id,))[0][0],
               'writer_batches':db_query('SELECT count(*) FROM writer_batches WHERE run_id=?',(run_id,))[0][0],
               'network_quality':qualities,
               'network_zero_samples':sum(row[1]=='measured' and row[3]==0 and row[4]==0 for row in fast),
               'network_window_s_median':statistics.median(row[5] for row in fast if row[1]=='measured') if qualities['measured'] else None,
               'fast_cadence_s':{'median':statistics.median(gaps),'max':max(gaps)},
               'observations':observations}
    assert db_query('PRAGMA integrity_check')[0][0] == 'ok'
    return summary

assert not OUT.exists(), f'{OUT} already exists'
assert db_query('PRAGMA user_version')[0][0] == 4
result = {'utc':datetime.now(timezone.utc).isoformat(),'binary_sha256':hashlib.sha256(APP.read_bytes()).hexdigest(),
          'method':'same ordinary binary; external libproc CPU/RSS; read-only SQLite; 60 second warmup; popover closed',
          'sampling_latency_ms':'not available from ordinary binary; fast cadence and standalone native sampler timing reported separately',
          'wakeups':'not available from external libproc sampling; context switches are reported, but are not wakeups',
          'energy_impact':'not available'}
try:
    result['A'] = run('A_disabled',600,True)
    OUT.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    result['B'] = run('B_enabled',900,False)
finally:
    OUT.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:{field:v[field] for field in ('duration_s','cpu_percent_one_core_after_warmup','rss_mb','fast_rows','network_quality','fast_cadence_s')}
                  for k,v in result.items() if k in ('A','B')},ensure_ascii=False))
