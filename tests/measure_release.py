#!/usr/bin/env python3
"""Read-only external resource comparison of the ordinary, uninstrumented app."""
import ctypes
import datetime
import hashlib
import json
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'app/SiliconMeter.app/Contents/MacOS/SiliconMeter'


class TaskInfo(ctypes.Structure):
    _fields_ = [(key, ctypes.c_uint64) for key in
                ('virtual_size', 'resident_size', 'total_user', 'total_system', 'threads_user', 'threads_system')] + [
                    (key, ctypes.c_int32) for key in ('policy', 'faults', 'pageins', 'cow_faults',
                    'messages_sent', 'messages_received', 'syscalls_mach', 'syscalls_unix', 'csw',
                    'threadnum', 'numrunning', 'priority')]


class Timebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]


def main():
    system = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    timebase = Timebase()
    if system.mach_timebase_info(ctypes.byref(timebase)) != 0 or not timebase.denom:
        raise RuntimeError('Mach timebase unavailable')
    seconds_per_tick = timebase.numer / timebase.denom / 1e9
    lib = ctypes.CDLL('/usr/lib/libproc.dylib')
    lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
    lib.proc_pidinfo.restype = ctypes.c_int
    rows = []
    with Path(sys.argv[1]).open('x') as out:
        app = subprocess.Popen([str(APP)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            start = time.monotonic()
            while time.monotonic() - start < 91:
                if app.poll() is not None:
                    raise RuntimeError('App exited early')
                info = TaskInfo()
                rc = lib.proc_pidinfo(app.pid, 4, 0, ctypes.byref(info), ctypes.sizeof(info))
                if rc != ctypes.sizeof(info):
                    raise RuntimeError('PROC_PIDTASKINFO unavailable')
                rows.append({'elapsed_s': time.monotonic() - start, 'rss_bytes': info.resident_size,
                             'cpu_s': (info.total_user + info.total_system) * seconds_per_tick, 'threads': info.threadnum})
                time.sleep(2)
            stable = [r for r in rows if r['elapsed_s'] >= 30]
            cpu = stable[-1]['cpu_s'] - stable[0]['cpu_s']
            duration = stable[-1]['elapsed_s'] - stable[0]['elapsed_s']
            json.dump({'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'pid': app.pid,
                       'binary_sha256': hashlib.sha256(APP.read_bytes()).hexdigest(),
                       'source_sha256': hashlib.sha256((ROOT/'app/ComputeMonitor.swift').read_bytes()).hexdigest(),
                       'mach_timebase': {'numer': timebase.numer, 'denom': timebase.denom},
                       'warmup_s': 30, 'duration_s': duration, 'cpu_s': cpu,
                       'cpu_percent_one_core': 100*cpu/duration,
                       'method': 'external libproc PROC_PIDTASKINFO; popover closed; no test hooks',
                       'samples': rows}, out, ensure_ascii=False, indent=2)
            out.write('\n')
        finally:
            if app.poll() is None:
                app.send_signal(signal.SIGTERM)
                app.wait(timeout=10)
    print('saved', sys.argv[1])


if __name__ == '__main__':
    main()
