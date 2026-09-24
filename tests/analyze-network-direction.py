"""Summarize passive native counters and read-only ordinary-app SQLite rows."""
import json
import sqlite3
import statistics
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs/results"
DB = Path.home() / "Library/Application Support/Compute Monitor/telemetry.sqlite3"
PHASES = ("baseline", "download", "cooldown", "upload", "recovery")


def phase_summary(phase, conn, run_id):
    source = json.loads((RESULTS / f"network-direction-{phase}.json").read_text())
    if source["app_run_id"] != run_id or source["interface"] != "en0":
        raise RuntimeError(f"App run/interface changed during {phase}")
    observations = source["observations"]
    if any([item["name"] for item in row["interfaces"]] != ["en0"]
           for row in observations):
        raise RuntimeError(f"Selected interface changed during {phase}")
    deltas = []
    for earlier, later in zip(observations, observations[1:]):
        a, b = earlier["interfaces"][0], later["interfaces"][0]
        dt = later["monotonic_s"] - earlier["monotonic_s"]
        rx, tx = b["rx_bytes"] - a["rx_bytes"], b["tx_bytes"] - a["tx_bytes"]
        if dt <= 0 or rx < 0 or tx < 0 or a["index"] != b["index"] or \
                a["link_change_s"] != b["link_change_s"]:
            raise RuntimeError(f"Native counter/index/link instability during {phase}")
        deltas.append((rx, tx, dt))
    duration = sum(item[2] for item in deltas)
    native = {}
    for direction, index in (("rx", 0), ("tx", 1)):
        total = sum(item[index] for item in deltas)
        native[direction] = {
            "total_bytes": total,
            "average_bytes_per_sec": total / duration,
            "peak_interval_bytes_per_sec": max(item[index] / item[2] for item in deltas),
        }
    rows = conn.execute(
        "SELECT utc_ms, network_rx_bytes_per_sec, network_tx_bytes_per_sec, "
        "network_rx_bytes_per_sec_quality, network_tx_bytes_per_sec_quality, "
        "network_rx_bytes_per_sec_window_s, network_tx_bytes_per_sec_window_s "
        "FROM fast_samples WHERE run_id=? AND utc_ms BETWEEN ? AND ? ORDER BY utc_ms",
        (run_id, source["start_utc_ms"], source["end_utc_ms"]),
    ).fetchall()
    if not rows:
        raise RuntimeError(f"No app SQLite rows during {phase}")
    windows = [value for row in rows for value in row[5:7] if value is not None]
    if not windows or any(not 0 < value <= 30 for value in windows):
        raise RuntimeError(f"Invalid app Δt during {phase}")
    if any(row[3:5] != ("measured", "measured") or
           row[1] is None or row[2] is None or row[1] < 0 or row[2] < 0
           for row in rows):
        raise RuntimeError(f"Unavailable, NULL, or negative app data during {phase}")
    app = {"rows": len(rows), "first_utc_ms": rows[0][0], "last_utc_ms": rows[-1][0],
           "window_s_min": min(windows), "window_s_max": max(windows)}
    for direction, index in (("rx", 1), ("tx", 2)):
        values = [row[index] for row in rows]
        app[direction] = {"average_bytes_per_sec": statistics.mean(values),
                          "peak_bytes_per_sec": max(values)}
    reference = source["reference"]
    if reference:
        if reference["interface_name"] != "en0":
            raise RuntimeError(f"networkQuality used another interface in {phase}")
        key = "dl_throughput" if phase == "download" else "ul_throughput"
        if not reference.get(key):
            raise RuntimeError(f"No throughput reference for {phase}")
    return {
        "start_utc_ms": source["start_utc_ms"], "end_utc_ms": source["end_utc_ms"],
        "duration_s": source["duration_s"], "native": native, "app_sqlite": app,
        "reference": reference,
    }


def main():
    phases = {name: json.loads((RESULTS / f"network-direction-{name}.json").read_text())
              for name in PHASES}
    run_id = phases["baseline"]["app_run_id"]
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        version = conn.execute("PRAGMA user_version").fetchone()[0]
        integrity = conn.execute("PRAGMA quick_check").fetchone()[0]
        if version != 4 or integrity != "ok":
            raise RuntimeError(f"SQLite version/integrity: {version}/{integrity}")
        summaries = {name: phase_summary(name, conn, run_id) for name in PHASES}
    finally:
        conn.close()
    baseline = summaries["baseline"]["app_sqlite"]
    down = summaries["download"]["app_sqlite"]
    up = summaries["upload"]["app_sqlite"]
    if not (down["rx"]["peak_bytes_per_sec"] > 10 * baseline["rx"]["average_bytes_per_sec"]
            and down["rx"]["average_bytes_per_sec"] > 10 * down["tx"]["average_bytes_per_sec"]
            and up["tx"]["peak_bytes_per_sec"] > 10 * baseline["tx"]["average_bytes_per_sec"]
            and up["tx"]["average_bytes_per_sec"] > 10 * up["rx"]["average_bytes_per_sec"]):
        raise RuntimeError("App direction response did not separate sufficiently")
    output = {"result": "PASS", "interface": "en0", "app_run_id": run_id,
              "sqlite_user_version": version, "sqlite_quick_check": integrity,
              "phases": summaries}
    path = RESULTS / "network-direction-summary.json"
    path.write_text(json.dumps(output, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"result": output["result"], "evidence": str(path)}, sort_keys=True))


if __name__ == "__main__":
    main()
