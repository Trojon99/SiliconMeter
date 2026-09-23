#!/usr/bin/env python3
"""Capture the single-process Step 2.6 stability run as full JSONL evidence."""
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
PROBE = HERE / "bin" / "telemetry-probe"
TRACE = HERE / "results" / "step26-2026-09-23.jsonl"
GROUPS = "public,gpu,power,temperature,memory,bandwidth"


def command_output(args):
    p = subprocess.run(args, capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if TRACE.exists():
        raise SystemExit(f"Refusing to overwrite existing trace: {TRACE}")
    TRACE.parent.mkdir(parents=True, exist_ok=True)
    metadata = {"kind": "metadata", "run_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "macos_version": command_output(["sw_vers", "-productVersion"]),
        "macos_build": command_output(["sw_vers", "-buildVersion"]),
        "chip": command_output(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "physical_bytes": command_output(["sysctl", "-n", "hw.memsize"]),
        "arch": command_output(["uname", "-m"]),
        "source_sha256": sha256(HERE / "telemetry_probe.m"),
        "binary_sha256": sha256(PROBE),
        "probe_argv": [str(PROBE), "--groups", GROUPS, "--stability"],
        "plan": [{"segment": i, "interval_s": 2 if i%2==0 else 5, "planned_duration_s": 120} for i in range(6)],
        "warmup_s": 30, "injected_delay": {"segment": 2, "sample_index": 30, "seconds": 6.2}}
    with TRACE.open("x") as output:
        output.write(json.dumps(metadata, ensure_ascii=False)+"\n")
        output.flush()
        process = subprocess.Popen(metadata["probe_argv"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        try:
            for line in process.stdout:
                row = json.loads(line)
                output.write(line)
                output.flush()
                if row.get("kind") in ("setup", "segment_end"):
                    print("received", row["kind"], row.get("segment", ""), flush=True)
            stderr = process.stderr.read()
            code = process.wait()
            print("exit", code, "stderr", stderr.strip(), flush=True)
            if code:
                raise SystemExit(code)
        finally:
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
    print("saved", TRACE, flush=True)


if __name__ == "__main__":
    main()
