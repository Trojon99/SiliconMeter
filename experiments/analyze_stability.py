#!/usr/bin/env python3
"""Summarize one complete Step 2.6 JSONL trace without discarding raw evidence."""
import argparse
import json
import pathlib
import statistics


def summary(values):
    if not values:
        return None
    values = sorted(values)
    return {"min": values[0], "median": statistics.median(values),
            "mean": statistics.mean(values), "p95": values[min(len(values)-1, int(len(values)*0.95))],
            "max": values[-1]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace", type=pathlib.Path)
    ap.add_argument("--output", type=pathlib.Path)
    args = ap.parse_args()
    rows = [json.loads(line) for line in args.trace.open() if line.strip()]
    metadata = next(r for r in rows if r["kind"] == "metadata")
    setup = next(r for r in rows if r["kind"] == "setup")
    segments = []
    for number in range(6):
        start = next(r for r in rows if r["kind"] == "segment_start" and r["segment"] == number)
        end = next(r for r in rows if r["kind"] == "segment_end" and r["segment"] == number)
        data = [r for r in rows if r["kind"] == "sample" and r.get("segment") == number]
        statuses = {}
        for r in data:
            v = r["values"]
            for label in ("cpu", "vm", "swap"):
                if label in v:
                    key = label + ":" + v[label]["status"]
                    statuses[key] = statuses.get(key, 0) + 1
            if "temperature" in v:
                for label, sensor in v["temperature"].items():
                    key = label + ":" + sensor["status"]
                    statuses[key] = statuses.get(key, 0) + 1
            for label, group in v.get("ioreport", {}).items():
                key = label + ":" + group["status"]
                statuses[key] = statuses.get(key, 0) + 1
        self_rows = [start["self"]] + [r["self"] for r in data] + [end["self"]]
        cpu_delta = end["self"]["cpu_seconds"] - start["self"]["cpu_seconds"]
        duration = end["monotonic_s"] - start["monotonic_s"]
        rss = [x["resident_bytes"] for x in self_rows if x["resident_bytes"] is not None]
        ports = [x["host_port_send_refs"] for x in self_rows if x["host_port_send_refs"] is not None]
        children = [x["child_process_count"] for x in self_rows if x["child_process_count"] is not None]
        wake_start, wake_end = start["self"], end["self"]
        segments.append({"segment": number, "nominal_interval_s": start["interval_s"],
                         "duration_s": duration, "samples": len(data),
                         "cpu_seconds": cpu_delta, "cpu_percent_one_core": 100*cpu_delta/duration,
                         "rss_first_bytes": rss[0], "rss_last_bytes": rss[-1],
                         "rss_observed_bytes": summary(rss), "host_port_refs": summary(ports),
                         "child_process_count": summary(children),
                         "tick_window_s": summary([r["tick_window_s"] for r in data if r["tick_window_s"] is not None]),
                         "latency_ms": summary([r["sampling_latency_ms"] for r in data]),
                         "statuses": statuses,
                         "interrupt_wakeups_delta": wake_end["interrupt_wakeups"]-wake_start["interrupt_wakeups"] if wake_end["interrupt_wakeups"] is not None and wake_start["interrupt_wakeups"] is not None else None,
                         "package_idle_wakeups_delta": wake_end["package_idle_wakeups"]-wake_start["package_idle_wakeups"] if wake_end["package_idle_wakeups"] is not None and wake_start["package_idle_wakeups"] is not None else None})
    injected = [r for r in rows if r["kind"] == "sample" and "injected_delay_s" in r]
    result = {"metadata": metadata, "setup": setup, "segments": segments,
              "warmup_samples": sum(r["kind"] == "sample" and r.get("phase") == "warmup" for r in rows),
              "injected_samples": [{"segment":r["segment"], "index":r["segment_index"],
                   "delay_s":r["injected_delay_s"], "tick_window_s":r["tick_window_s"],
                   "gpu_power_window_s":r["values"].get("ioreport",{}).get("power",{}).get("window_s"),
                   "gpu_estimated_w":r["values"].get("ioreport",{}).get("power",{}).get("gpu_estimated_w"),
                   "bandwidth_window_s":r["values"].get("ioreport",{}).get("bandwidth",{}).get("window_s"),
                   "gfx_dcs_traffic_gbs":r["values"].get("ioreport",{}).get("bandwidth",{}).get("gfx_dcs_traffic_gbs")}
                   for r in injected]}
    if args.output:
        args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False)+"\n")
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
