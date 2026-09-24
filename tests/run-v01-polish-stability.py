#!/usr/bin/env python3
"""Observe one ordinary App PID for 10m idle, 10m local compute, 10m recovery."""
import ctypes
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sqlite3
import statistics
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "app/ComputeMonitor.app/Contents/MacOS/ComputeMonitor"
DB = Path.home() / "Library/Application Support/Compute Monitor/telemetry.sqlite3"
RAW = ROOT / "docs/results/v01-polish-stability.jsonl"
SUMMARY = ROOT / "docs/results/v01-polish-stability-summary.json"
PHASE_SECONDS = 600
TOTAL_SECONDS = 3 * PHASE_SECONDS


class TaskInfo(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in
                ("virtual_size", "resident_size", "total_user", "total_system",
                 "threads_user", "threads_system")] + [
                     (name, ctypes.c_int32) for name in
                     ("policy", "faults", "pageins", "cow_faults", "messages_sent",
                      "messages_received", "syscalls_mach", "syscalls_unix", "csw",
                      "threadnum", "numrunning", "priority")]


libsystem = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
libproc.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                 ctypes.c_void_p, ctypes.c_int]
libproc.proc_pidinfo.restype = ctypes.c_int
timebase = (ctypes.c_uint32 * 2)()
if libsystem.mach_timebase_info(timebase) != 0 or not timebase[1]:
    raise RuntimeError("Mach timebase unavailable")
seconds_per_tick = timebase[0] / timebase[1] / 1e9


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def processes():
    records = []
    for line in subprocess.check_output(["ps", "-axo", "pid=,ppid=,args="], text=True).splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
            records.append((int(parts[0]), int(parts[1]), parts[2]))
    return records


def task(pid):
    info = TaskInfo()
    rc = libproc.proc_pidinfo(pid, 4, 0, ctypes.byref(info), ctypes.sizeof(info))
    if rc != ctypes.sizeof(info):
        raise RuntimeError("PROC_PIDTASKINFO unavailable")
    return {"cpu_s": (info.total_user + info.total_system) * seconds_per_tick,
            "rss_mib": info.resident_size / 1048576,
            "threads": info.threadnum, "context_switches": info.csw}


def database():
    with sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=5) as conn:
        version = conn.execute("PRAGMA user_version").fetchone()[0]
        pages = conn.execute("PRAGMA page_count").fetchone()[0]
        size = conn.execute("PRAGMA page_size").fetchone()[0]
        run_id = conn.execute("SELECT run_id FROM app_runs ORDER BY start_utc_ms DESC LIMIT 1").fetchone()[0]
        return {"version": version, "run_id": run_id, "logical_bytes": pages * size,
                "fast_rows": conn.execute("SELECT count(*) FROM fast_samples WHERE run_id=?", (run_id,)).fetchone()[0],
                "slow_rows": conn.execute("SELECT count(*) FROM slow_samples WHERE run_id=?", (run_id,)).fetchone()[0],
                "writer_batches": conn.execute("SELECT count(*) FROM writer_batches WHERE run_id=?", (run_id,)).fetchone()[0]}


def socket_and_child_counts(pid):
    rows = processes()
    sockets = subprocess.run(["lsof", "-nP", "-a", "-p", str(pid), "-i"],
                             capture_output=True, text=True, timeout=10).stdout.splitlines()
    return {"children": sum(parent == pid for _, parent, _ in rows),
            "network_sockets": max(0, len(sockets) - 1)}


def emit(out, record):
    out.write(json.dumps(record, sort_keys=True) + "\n")
    out.flush()


def phase_at(tick):
    return "idle" if tick < 40 else "local_compute" if tick < 80 else "recovery"


def summarize(rows, run_id, started, ended):
    with sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=5) as conn:
        integrity = conn.execute("PRAGMA quick_check").fetchone()[0]
        columns = {table: [row[1] for row in conn.execute(f"PRAGMA table_info({table})")
                   if row[1].endswith("_quality")] for table in ("fast_samples", "slow_samples")}
        qualities = {}
        for table, fields in columns.items():
            qualities[table] = {}
            for quality in ("measured", "estimated", "unavailable", "invalid", "stale"):
                expression = " + ".join(f"({field}='{quality}')" for field in fields)
                qualities[table][quality] = conn.execute(
                    f"SELECT coalesce(sum({expression}),0) FROM {table} WHERE run_id=?",
                    (run_id,)).fetchone()[0]
        times = [row[0] for row in conn.execute(
            "SELECT utc_ms FROM fast_samples WHERE run_id=? ORDER BY seq", (run_id,))]
        gaps = [(b-a)/1000 for a,b in zip(times,times[1:])]
    per_phase = {}
    for phase in ("idle", "local_compute", "recovery"):
        subset = [row for row in rows if row["phase"] == phase]
        if len(subset) < 2:
            raise RuntimeError(f"Missing phase observations: {phase}")
        cpu_s = subset[-1]["process"]["cpu_s"] - subset[0]["process"]["cpu_s"]
        duration = subset[-1]["elapsed_s"] - subset[0]["elapsed_s"]
        per_phase[phase] = {"duration_observed_s": duration, "cpu_s": cpu_s,
                            "cpu_percent_one_core": 100*cpu_s/duration,
                            "rss_mib_mean": statistics.mean(row["process"]["rss_mib"] for row in subset),
                            "rss_mib_peak": max(row["process"]["rss_mib"] for row in subset)}
    all_cpu = rows[-1]["process"]["cpu_s"] - rows[0]["process"]["cpu_s"]
    all_duration = rows[-1]["elapsed_s"] - rows[0]["elapsed_s"]
    return {"result": "PASS", "run_id": run_id, "binary_sha256": hashlib.sha256(APP.read_bytes()).hexdigest(),
            "started_utc": started, "ended_utc": ended, "duration_s": all_duration,
            "observation_count": len(rows), "cpu_time_s": all_cpu,
            "cpu_percent_one_core": 100*all_cpu/all_duration,
            "rss_mib_mean": statistics.mean(row["process"]["rss_mib"] for row in rows),
            "rss_mib_peak": max(row["process"]["rss_mib"] for row in rows),
            "phases": per_phase, "fast_cadence_s": {"median": statistics.median(gaps),
                                                 "max": max(gaps), "count": len(gaps)},
            "qualities": qualities, "sqlite_quick_check": integrity,
            "database_logical_growth_bytes": rows[-1]["database"]["logical_bytes"] -
                                              rows[0]["database"]["logical_bytes"],
            "fast_rows_added": rows[-1]["database"]["fast_rows"] - rows[0]["database"]["fast_rows"],
            "slow_rows_added": rows[-1]["database"]["slow_rows"] - rows[0]["database"]["slow_rows"],
            "writer_batches_added": rows[-1]["database"]["writer_batches"] -
                                    rows[0]["database"]["writer_batches"],
            "sampling_latency_note": "not directly observable from ordinary binary; fast cadence and separate collector fixture are reported",
            "timer_count_note": "runtime count unavailable; source retains one DispatchSourceTimer",
            "phase_workload": "one external local SHA-256 CPU process for middle 600 seconds; no network or file input"}


def main():
    if RAW.exists() or SUMMARY.exists():
        raise RuntimeError("Polish stability result already exists")
    matches = [(pid,parent) for pid,parent,args in processes() if args == str(APP)]
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one ordinary App: {matches}")
    pid = matches[0][0]
    initial_db = database()
    if initial_db["version"] != 4:
        raise RuntimeError("Expected SQLite v4")
    run_id = initial_db["run_id"]
    rows = []
    workload = None
    start = time.monotonic()
    started = timestamp()
    with RAW.open("x") as out:
        emit(out, {"kind": "start", "utc": started, "pid": pid, "run_id": run_id,
                   "binary_sha256": hashlib.sha256(APP.read_bytes()).hexdigest(),
                   "database": initial_db, "process": task(pid),
                   **socket_and_child_counts(pid)})
        try:
            for tick in range(121):
                target = tick * 15
                delay = start + target - time.monotonic()
                if delay > 0:
                    time.sleep(delay)
                elapsed = time.monotonic() - start
                if tick == 40:
                    program = ("import hashlib,time\n"
                               "payload=b'v01-polish-local-compute'*4096\n"
                               "end=time.monotonic()+600\n"
                               "while time.monotonic()<end: hashlib.sha256(payload).digest()\n")
                    workload = subprocess.Popen([sys.executable, "-c", program],
                                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if tick == 80 and workload is not None:
                    if workload.poll() is None:
                        workload.terminate()
                    workload.wait(timeout=10)
                    workload = None
                matches = [(candidate,parent) for candidate,parent,args in processes()
                           if args == str(APP)]
                if len(matches) != 1 or matches[0][0] != pid:
                    raise RuntimeError(f"App PID changed at {elapsed:.1f}s: {matches}")
                info = task(pid)
                db = database()
                if db["version"] != 4 or db["run_id"] != run_id:
                    raise RuntimeError("SQLite version or App run changed")
                record = {"kind": "sample", "elapsed_s": round(elapsed, 3),
                          "utc": timestamp(), "phase": phase_at(tick),
                          "process": info, "database": db}
                if tick in (0, 40, 80, 120):
                    record.update(socket_and_child_counts(pid))
                    print(f"POLISH_STABILITY {tick//40}/3 elapsed={elapsed:.1f}s "
                          f"phase={record['phase']} rss={info['rss_mib']:.2f}MiB", flush=True)
                rows.append(record)
                emit(out, record)
        finally:
            if workload is not None:
                if workload.poll() is None:
                    workload.terminate()
                workload.wait(timeout=10)
    summary = summarize(rows, run_id, started, timestamp())
    SUMMARY.write_text(json.dumps(summary, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"result": summary["result"], "summary": str(SUMMARY),
                      "duration_s": summary["duration_s"]}), flush=True)


if __name__ == "__main__":
    main()
