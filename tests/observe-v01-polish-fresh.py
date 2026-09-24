#!/usr/bin/env python3
"""90-second closed-popover, ordinary-App resource cross-check after the long run."""
import ctypes
from datetime import datetime, timezone
import json
from pathlib import Path
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
APP = str(Path(sys.argv[1]).resolve()) if len(sys.argv) > 1 else str(ROOT / "app/ComputeMonitor.app/Contents/MacOS/ComputeMonitor")
OUT = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "docs/results/v01-polish-fresh-closed.json"


class TaskInfo(ctypes.Structure):
    _fields_ = [(key, ctypes.c_uint64) for key in
                ("virtual_size", "resident_size", "total_user", "total_system",
                 "threads_user", "threads_system")] + [
                     (key, ctypes.c_int32) for key in
                     ("policy", "faults", "pageins", "cow_faults", "messages_sent",
                      "messages_received", "syscalls_mach", "syscalls_unix", "csw",
                      "threadnum", "numrunning", "priority")]

system = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
lib = ctypes.CDLL("/usr/lib/libproc.dylib")
lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                             ctypes.c_void_p, ctypes.c_int]
lib.proc_pidinfo.restype = ctypes.c_int
timebase = (ctypes.c_uint32 * 2)()
assert system.mach_timebase_info(timebase) == 0 and timebase[1]
seconds_per_tick = timebase[0] / timebase[1] / 1e9


def pid():
    matches = []
    for line in subprocess.check_output(["ps", "-axo", "pid=,args="], text=True).splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[1] == APP:
            matches.append(int(parts[0]))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one ordinary App: {matches}")
    return matches[0]


def sample(target):
    info = TaskInfo()
    if lib.proc_pidinfo(target, 4, 0, ctypes.byref(info), ctypes.sizeof(info)) != ctypes.sizeof(info):
        raise RuntimeError("PROC_PIDTASKINFO unavailable")
    return {"cpu_s": (info.total_user + info.total_system) * seconds_per_tick,
            "rss_mib": info.resident_size / 1048576}


def main():
    if OUT.exists():
        raise RuntimeError("Result already exists")
    target = pid()
    start = time.monotonic()
    rows = []
    for index in range(19):
        delay = start + index * 5 - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        if pid() != target:
            raise RuntimeError("App PID changed")
        rows.append({"elapsed_s": time.monotonic()-start, **sample(target)})
    steady = [row for row in rows if row["elapsed_s"] >= 30]
    cpu_s = steady[-1]["cpu_s"] - steady[0]["cpu_s"]
    duration = steady[-1]["elapsed_s"] - steady[0]["elapsed_s"]
    result = {"utc": datetime.now(timezone.utc).isoformat(), "pid": target,
              "duration_s": rows[-1]["elapsed_s"], "warmup_s": 30,
              "cpu_percent_one_core_after_warmup": 100*cpu_s/duration,
              "cpu_time_s_after_warmup": cpu_s,
              "rss_mib_mean_after_warmup": statistics.mean(row["rss_mib"] for row in steady),
              "rss_mib_final": rows[-1]["rss_mib"],
              "rss_mib_peak_sampled": max(row["rss_mib"] for row in rows),
              "app_path": APP,
              "method": "external libproc on a freshly relaunched ordinary App; popover left closed",
              "observations": rows}
    OUT.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"cpu_percent_one_core_after_warmup": result["cpu_percent_one_core_after_warmup"],
                      "rss_mib_final": result["rss_mib_final"], "evidence": str(OUT)}))


if __name__ == "__main__":
    main()
