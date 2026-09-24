"""Test-only passive counter recorder around one bounded Apple networkQuality run."""
import argparse
import json
import sqlite3
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / ".build/network-direction-probe"
RESULTS = ROOT / "docs/results"
PRIVATE = ROOT / ".build/network-direction"
DB = Path.home() / "Library/Application Support/SiliconMeter/telemetry.sqlite3"


def sample():
    result = subprocess.run([str(PROBE), "--sample"], capture_output=True,
                            text=True, timeout=3, check=True)
    return json.loads(result.stdout)


def current_run():
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=3)
    try:
        row = conn.execute("SELECT run_id, start_utc_ms FROM app_runs "
                           "ORDER BY start_utc_ms DESC LIMIT 1").fetchone()
        if row is None:
            raise RuntimeError("No ordinary app run in the v4 database")
        return {"run_id": row[0], "start_utc_ms": row[1]}
    finally:
        conn.close()


def record_until(deadline, observations):
    while time.monotonic() < deadline:
        observations.append(sample())
        time.sleep(min(1.0, max(0.0, deadline - time.monotonic())))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=["baseline", "download", "cooldown", "upload", "recovery"])
    parser.add_argument("--seconds", type=int, required=True)
    parser.add_argument("--interface", default="en0")
    parser.add_argument("--no-bind", action="store_true",
                        help="Use system routing when networkQuality -I fails; verify reported interface")
    args = parser.parse_args()
    if not 5 <= args.seconds <= 120:
        parser.error("seconds must be 5..120")
    PRIVATE.mkdir(parents=True, exist_ok=True)
    run = current_run()
    observations = [sample()]
    selected = [item["name"] for item in observations[0]["interfaces"]]
    if selected != [args.interface]:
        raise RuntimeError(f"Selected interfaces {selected} differ from bound interface {args.interface}")
    start_utc_ms = int(time.time() * 1000)
    start_monotonic = time.monotonic()
    command = None
    returncode = None
    if args.phase in ("download", "upload"):
        command = ["/usr/bin/networkQuality"]
        if not args.no_bind:
            command += ["-I", args.interface]
        command += ["-u" if args.phase == "download" else "-d",
                    "-M", str(args.seconds), "-c"]
        stdout_path = PRIVATE / f"{args.phase}.stdout"
        stderr_path = PRIVATE / f"{args.phase}.stderr"
        with stdout_path.open("w") as stdout, stderr_path.open("w") as stderr:
            process = subprocess.Popen(command, stdout=stdout, stderr=stderr)
            try:
                deadline = start_monotonic + args.seconds + 12
                while process.poll() is None and time.monotonic() < deadline:
                    observations.append(sample())
                    time.sleep(1)
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                    raise RuntimeError("networkQuality exceeded bounded test deadline")
                returncode = process.returncode
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=3)
    else:
        record_until(start_monotonic + args.seconds, observations)
    observations.append(sample())
    reference = None
    if command is not None:
        reference = json.loads(stdout_path.read_text())
        if reference.get("interface_name") != args.interface or "error_code" in reference:
            raise RuntimeError(f"networkQuality did not complete on {args.interface}: "
                               f"{reference.get('error_domain')} {reference.get('error_code')} "
                               f"interface={reference.get('interface_name')}")
        throughput_key = "dl_throughput" if args.phase == "download" else "ul_throughput"
        if not reference.get(throughput_key):
            raise RuntimeError(f"networkQuality omitted {throughput_key}")
    result = {
        "phase": args.phase, "command": command, "network_quality_returncode": returncode,
        "interface": args.interface, "app_run_id": run["run_id"],
        "app_run_start_utc_ms": run["start_utc_ms"],
        "start_utc_ms": start_utc_ms, "end_utc_ms": int(time.time() * 1000),
        "duration_s": time.monotonic() - start_monotonic,
        "reference": {k: reference.get(k) for k in (
            "interface_name", "dl_throughput", "dl_bytes_transferred", "dl_phase_duration",
            "ul_throughput", "ul_bytes_transferred", "ul_phase_duration", "test_endpoint"
        ) if k in reference} if reference else None,
        "observations": observations,
    }
    path = RESULTS / f"network-direction-{args.phase}.json"
    path.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"phase": args.phase, "duration_s": round(result["duration_s"], 2),
                      "samples": len(observations), "returncode": returncode,
                      "evidence": str(path)}, sort_keys=True), flush=True)
    if returncode not in (None, 0):
        raise RuntimeError(f"networkQuality exited {returncode}; see {PRIVATE / (args.phase + '.stderr')}")


if __name__ == "__main__":
    main()
