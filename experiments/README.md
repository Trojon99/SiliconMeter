# Step 2 telemetry experiments

This directory is a disposable validation harness for the Apple M1 Max on macOS
27.0 (26A428). It is separate from any future menu-bar application. Nothing is
installed and the probe does not start a persistent subprocess or use the network.

Build with `sh experiments/build.sh`. The build output is ignored by Git.

The probe emits one JSON object per line. Its first line describes channel
enumeration, selection and subscription. Each later line contains raw counter
deltas, statuses, sampling latency and the probe's own process counters.

Examples:

```sh
experiments/bin/telemetry-probe --groups public --interval 2 --samples 5
experiments/bin/telemetry-probe --groups public,gpu,power,temperature,memory,bandwidth --interval 2 --samples 5
experiments/bin/telemetry-probe --groups gpu,power,cpustates,bandwidth,pmp --inspect --samples 2
```

Groups are independent: `public`, `gpu`, `power`, `temperature`, `memory`,
`bandwidth`, `cpustates`, `pmp`, and `ane` (ANE reuses the power subscription).
The `--unfiltered` option is diagnostic only; it asks IOReport for every channel
in a selected group. Do not use it for overhead comparisons.
Temperature defaults to the validated `Tp05` and `Tg05` keys; `--inspect`
additionally tests other candidate keys and records failures.

The bounded load modes are `cpu-single`, `cpu-multi`, `gpu-moderate`,
`gpu-heavy`, and `gpu-bandwidth`, with `--duration` in seconds. The Python
runner starts these as separate temporary processes so their CPU time is not
included in the monitor's CPU-time counter. It waits for every load process to
exit. Run the measured matrix with:

```sh
python3 experiments/run_experiments.py --phase loads --output /tmp/telemetry_loads.json
python3 experiments/run_experiments.py --phase overhead --output /tmp/telemetry_overhead.json
```

The source uses public Mach, Foundation, Metal and IOKit entry points, plus
private `libIOReport` symbols and the undocumented AppleSMC request protocol.
The kernel's IOReport channel names and chip DVFS table are not stable API.
The same unsigned CLI was tested both within the Codex sandbox and as the
current user on the host. The sandbox can reject IOReport subscriptions, SMC
connections and some sysctls even when ordinary-user host execution succeeds.

The probe prints raw energy units and byte deltas. CPU and GPU energy rails
must never be summed blindly. A zero delta on an unvalidated counter is not
proof of zero device power. GPU weighted frequency is an estimate over active
residency, not an instantaneous clock. The workload test validates the mapping
of GPUPH P1–P6 to the six active M1 Max frequencies in `voltage-states9`.

`proc_pid_rusage` supplies process CPU time, resident bytes and package idle
wakeup counters. These are measured counters, but package idle wakeups may stay
zero on a busy machine; they are not an Energy Impact estimate. JSON encoding
and Foundation are part of this experiment's overhead.

Implementation ideas were checked against the MIT-licensed macmon, mactop,
Stats and SiliconScope projects. No external source code was copied into the
probe.

## Step 2.6 validity and stability run

The current probe emits each rate's own monotonic `window_s`. The JSONL
`nominal_interval_s` describes scheduling only; use `window_s` for energy,
traffic and swap activity rates. A failed counter sample clears its baseline;
the next successful read establishes a new baseline without a rate. Windows
longer than 30 seconds (or ten requested intervals, whichever is longer) are
marked stale and rebased. Late timer firings schedule their next sample from
the actual completion time, with no catch-up burst.

The Step 2.6 run is one process, with a 30-second warmup and six 120-second
segments at 2, 5, 2, 5, 2 and 5 seconds. One 6.2-second scheduling delay is
injected in the third segment. Run on the ordinary-user host, where IOReport
and SMC access were validated:

```sh
sh experiments/build.sh
python3 experiments/run_stability.py
python3 experiments/analyze_stability.py experiments/results/step26-2026-09-23.jsonl \
  --output experiments/results/step26-2026-09-23-summary.json
```

The runner refuses to overwrite a prior trace. The JSONL file contains every
sample and segment boundary, preceded by exact machine, OS build, source hash,
binary hash and command metadata. The summary is derived from this retained
trace. `GFX DCS` traffic remains experimental and is not approved as a v0.1
memory-bandwidth metric by this run.
