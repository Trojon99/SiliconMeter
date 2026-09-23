#!/usr/bin/env python3
"""Run bounded Step-2 measurements; store compact summaries, not full traces."""
import argparse
import json
import os
import pathlib
import statistics
import subprocess
import time
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).resolve().parent
PROBE = HERE / "bin" / "telemetry-probe"


def avg(values):
    return round(statistics.mean(values), 5) if values else None


def range_summary(values):
    return {"min": round(min(values), 5), "mean": avg(values), "max": round(max(values), 5)} if values else None


def channel(sample, group, name):
    group_data = sample.get("values", {}).get("ioreport", {}).get(group, {})
    if group_data.get("status") != "measured":
        return None
    matches = [c for c in group_data.get("channels", []) if c["name"] == name]
    return matches[0] if len(matches) == 1 else None


def gpu_active(sample):
    c = channel(sample, "gpu", "GPUPH")
    if not c:
        return None
    states = c.get("states", [])
    total = sum(x["ticks"] for x in states if x["ticks"] >= 0)
    inactive = sum(x["ticks"] for x in states if x["state"].strip() in ("OFF", "IDLE"))
    return (total - inactive) / total if total > 0 else None


def watts(sample, name):
    if name != "GPU Energy":
        return None  # Unvalidated rails must not be summarized as 0 W.
    group = sample.get("values", {}).get("ioreport", {}).get("power", {})
    c = channel(sample, "power", name)
    if not c or c.get("delta") is None or c["delta"] < 0 or group.get("gpu_power_status") != "estimated":
        return None
    unit = c["unit"]
    joules = c["delta"] * {"mJ": 1e-3, "uJ": 1e-6, "nJ": 1e-9}.get(unit, float("nan"))
    window = group.get("window_s")
    return joules / window if window and window > 0 and unit == "nJ" else None


def bandwidth(sample, prefix):
    group = sample.get("values", {}).get("ioreport", {}).get("bandwidth", {})
    if group.get("status") != "measured" or not group.get("window_s"):
        return None
    values = group.get("channels", [])
    selected = []
    for suffix in ("DCS RD", "DCS WR"):
        matches = [c for c in values if c["name"] == prefix + suffix]
        if len(matches) != 1 or matches[0].get("unit") != "B" or matches[0].get("delta", -1) < 0:
            return None
        selected.append(matches[0]["delta"])
    return sum(selected) / group["window_s"] / 1e9


def run(groups, interval, samples, workload=None, inspect=False):
    load = None
    if workload and workload != "idle":
        load = subprocess.Popen([str(PROBE), "--load", workload, "--duration", str(interval * samples + 2)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        time.sleep(0.35)
    command = [str(PROBE), "--groups", groups, "--interval", str(interval), "--samples", str(samples)]
    if inspect:
        command.append("--inspect")
    started = time.monotonic()
    process = subprocess.run(command, capture_output=True, text=True, check=False)
    elapsed = time.monotonic() - started
    load_info = None
    if load:
        _, load_stderr = load.communicate(timeout=30)
        load_info = {"exit_code": load.returncode, "stderr": load_stderr.strip()}
    if process.returncode:
        raise RuntimeError(f"probe exited {process.returncode}: {process.stderr}")
    rows = [json.loads(line) for line in process.stdout.splitlines()]
    if len(rows) != samples + 1:
        raise RuntimeError(f"expected {samples + 1} JSONL rows, got {len(rows)}: {process.stderr}")
    setup, data = rows[0], rows[1:]
    start_self, end_self = data[0]["self"], data[-1]["self"]
    live_window = data[-1]["monotonic_s"] - data[0]["monotonic_s"]
    wake = lambda key: (end_self[key] - start_self[key]) if start_self[key] is not None and end_self[key] is not None else None
    overhead = {
        "cpu_seconds_between_first_last": round(wake("cpu_seconds"), 6),
        "cpu_percent_one_core_between_first_last": round(100 * wake("cpu_seconds") / live_window, 4) if live_window else None,
        "resident_bytes": range_summary([r["self"]["resident_bytes"] for r in data if r["self"]["resident_bytes"] is not None]),
        "sampling_latency_ms": range_summary([r["sampling_latency_ms"] for r in data]),
        "package_idle_wakeups_delta": wake("package_idle_wakeups"),
        "interrupt_wakeups_delta": wake("interrupt_wakeups"),
        "context_switches_delta": wake("voluntary_context_switches") + wake("involuntary_context_switches"),
        "subscribed_channels": {k: v.get("subscribed", 0) for k, v in setup["ioreport"].items() if isinstance(v, dict)},
        "non_sample_rows": len(rows) - samples,
    }
    metrics = {
        "cpu_total": range_summary([r["values"]["cpu"]["total"] for r in data if r["values"].get("cpu", {}).get("status") == "measured"]),
        "cpu_p": range_summary([r["values"]["cpu"]["p"] for r in data if r["values"].get("cpu", {}).get("status") == "measured"]),
        "cpu_e": range_summary([r["values"]["cpu"]["e"] for r in data if r["values"].get("cpu", {}).get("status") == "measured"]),
        "gpu_active": range_summary([x for r in data if (x := gpu_active(r)) is not None]),
        "gpu_weighted_active_frequency_mhz": range_summary([r["values"]["ioreport"]["gpu"]["weighted_active_frequency_mhz"] for r in data if r["values"].get("ioreport", {}).get("gpu", {}).get("frequency_status") == "estimated"]),
        "power_cpu_energy_w": range_summary([x for r in data if (x := watts(r, "CPU Energy")) is not None]),
        "power_gpu0_w": range_summary([x for r in data if (x := watts(r, "GPU0")) is not None]),
        "power_gpu_energy_w": range_summary([x for r in data if (x := watts(r, "GPU Energy")) is not None]),
        "power_ane0_w": range_summary([x for r in data if (x := watts(r, "ANE0")) is not None]),
        "bandwidth_gpu_gbs": range_summary([x for r in data if (x := bandwidth(r, "GFX ")) is not None]),
        "bandwidth_p0_gbs": range_summary([x for r in data if (x := bandwidth(r, "PCPU0 ")) is not None]),
        "temperature_cpu_c": range_summary([r["values"]["temperature"]["Tp05"]["celsius"] for r in data if r["values"].get("temperature", {}).get("Tp05", {}).get("status") == "measured"]),
        "temperature_gpu_c": range_summary([r["values"]["temperature"]["Tg05"]["celsius"] for r in data if r["values"].get("temperature", {}).get("Tg05", {}).get("status") == "measured"]),
    }
    failures = {}
    for r in data:
        for group, value in r["values"].get("ioreport", {}).items():
            if value["status"] != "measured":
                failures[group] = failures.get(group, 0) + 1
    return {"groups": groups, "interval_s": interval, "samples": samples, "workload": workload or "idle",
            "elapsed_s": round(elapsed, 3), "setup": setup["ioreport"], "metrics": metrics,
            "overhead": overhead, "failures": failures, "load": load_info,
            "representative_sample": data[len(data) // 2]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", choices=("loads", "overhead"), required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--only", help="comma-separated workload names for the loads phase")
    parser.add_argument("--configs", help="comma-separated configuration labels for the overhead phase")
    args = parser.parse_args()
    result = {"phase": args.phase, "run_at_utc": datetime.now(timezone.utc).isoformat(),
              "os": "macOS 27.0 (26A428)", "chip": "Apple M1 Max", "cpu": "8 P + 2 E", "memory_bytes": 68719476736,
              "runs": []}
    if args.phase == "loads":
        groups = "public,gpu,power,cpustates,temperature,memory,bandwidth,ane"
        jobs = [("idle", 1, 8), ("cpu-single", 1, 8), ("cpu-multi", 1, 8),
                ("gpu-moderate", 1, 10), ("gpu-heavy", 1, 12), ("gpu-bandwidth", 1, 10)]
        if args.only:
            allowed = set(args.only.split(","))
            jobs = [job for job in jobs if job[0] in allowed]
        for load, interval, samples in jobs:
            print(f"load {load} {samples}s", flush=True)
            result["runs"].append(run(groups, interval, samples, load, inspect=False))
    else:
        configs = [("A", "public"), ("B", "public,gpu"), ("C", "public,gpu,power"),
                   ("D", "public,gpu,power,temperature"),
                   ("E", "public,gpu,power,temperature,bandwidth")]
        if args.configs:
            allowed = set(args.configs.split(","))
            configs = [config for config in configs if config[0] in allowed]
        for label, groups in configs:
            for interval, samples in ((1, 5), (2, 4), (5, 3)):
                print(f"overhead {label} {interval}s x{samples}", flush=True)
                row = run(groups, interval, samples)
                row["configuration"] = label
                result["runs"].append(row)
    path = pathlib.Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(f"saved {path}", flush=True)


if __name__ == "__main__":
    main()
