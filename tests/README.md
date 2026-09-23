# Step 3.1 review checks

These are test tools, not product logging. No third-party dependency is required.
The production build excludes all `STEP31_REVIEW` hooks.

```sh
sh tests/run-checks.sh
sh tests/build-review.sh
python3 tests/run_step31.py docs/results/a-new-run.jsonl
python3 tests/analyze_step31.py docs/results/a-new-run.jsonl --output docs/results/a-new-summary.json
```

Run the long test in the ordinary user's graphical macOS session, outside the
Codex shell sandbox and App Sandbox. It takes 30 seconds of warmup plus at least
30 minutes, uses one AppKit app PID, and starts the existing `gpu-heavy` Metal
workload after 10 minutes. The runner refuses to overwrite evidence. The app
writes observations to stdout; the external runner owns the JSONL file. The
workload is a sibling of the app, and both are reaped by the runner. Primary
selection is exercised through real NSButton actions but not saved to defaults
in the review variant. This is the only production behavior suppressed by that
flag besides the test-only resource capture and UI driver.

The review callback runs from the existing scheduler and creates no timer or
collector. Each phase has two 60-second toggle/metric-selection periods and two
60-second held-open periods. Remaining time is closed; warmup is closed. The
trace records actual popover visibility, controls used, timing, and resource
readings. Counts include one startup slow sample which is not a trace tick.
Quality totals in the analyzer count fresh readings, not cached snapshot values.
Sampling latency excludes self-observation, JSON and UI work; process CPU time
includes them. `getrusage.ru_maxrss` is the kernel high-water RSS on this macOS;
`proc_pid_rusage` supplies current RSS. The two wakeup counters are OS-defined
categories, not a complete count of wakeups or Energy Impact.

The fault suite substitutes low-level calls in a translation unit that directly
includes the production backend. It covers VM failure propagation/recovery,
CPU counter rollback and wrap, topology gating, actual rate windows, IOReport
failure/baseline/sentinel/unit/state paths, SMC metadata caching and recovery.
The Swift suite uses the production declarations without the application entry
point, tests quality/age rendering, repeated start, actual scheduling,
thermal-observer duplication/removal, and release after stop.

Optional ordinary-build comparison (after the long app has exited):

```sh
sh app/build.sh
python3 tests/measure_release.py docs/results/a-new-release-comparison.json
```

This starts the ordinary app with no test hooks, warms it for 30 seconds, then
measures about 60 seconds externally with libproc and terminates only that PID.
It is a short instrumentation-overhead comparison, not a replacement for the
single-process long test.

`ui_layout_check.py` creates `.build/step31-ui.swift`, a temporary version of the
existing UI smoke entry point with view-frame reporting and an offscreen bitmap.
Compile it with `-D STEP3_UI_SMOKE` and the normal backend object, as in
`app/ui-smoke.sh`. Hosted AppKit controls do not fully render into that offscreen
bitmap; frame containment and the real popover smoke are the checks used here.

Additional lifecycle checks compile the real backend directly:

```sh
clang -O1 -g -fsanitize=address -fno-omit-frame-pointer -mmacosx-version-min=13.0 -fobjc-arc -fblocks tests/ioreport_ownership.m -framework Foundation -framework IOKit -o .build/ownership-check
.build/ownership-check
clang -O1 -g -fsanitize=address -fno-omit-frame-pointer -mmacosx-version-min=13.0 -fobjc-arc -fblocks tests/backend_lifecycle.m -framework Foundation -framework IOKit -o .build/lifecycle-check
.build/lifecycle-check
```

Run ownership checking both in a denied sandbox and in the ordinary user session;
the output distinguishes whether subscriptions succeeded. It retains the input
once for observation, drains the inner pool and subscription resources, and
expects only that protective reference to remain. The lifecycle stress performs
10 warmups and 100 real create/sample/shutdown cycles and compares host rights
and port-name counts. ASan detects memory access errors, not all leak classes.

The saved September 23 long trace predates the final popover height and two
initialization-input releases. The exact difference is retained in
`docs/results/step31-post-start-fixes.patch`; all sampling/scheduler/quality fixes
were already in that long-run binary. The later checks cover the final sources.

## Step 3.2 history checks

```sh
sh app/build.sh
python3 tests/run-history-checks.py
sh tests/build-review.sh
python3 tests/run_step32.py docs/results/a-new-step32.jsonl
python3 tests/analyze_step32.py docs/results/a-new-step32.jsonl
python3 tests/run-app-crash.py docs/results/a-new-app-crash.json
python3 tests/measure_release.py docs/results/a-new-release-comparison.json
```

`run-history-checks.py` uses isolated temporary databases. It checks schema,
UTC/quality semantics, app runs, sample/event tables, WAL read-only access while
a writer is active, normal flush, reopening, and a controlled SIGKILL with one
committed and one uncommitted sample. The long runner uses production source
with the same Step 3.1 observation hooks, plus external read-only SQLite/file
observations approximately every 30 seconds. It performs 30 seconds of warmup,
then idle, existing GPU load, and recovery phases of about 10 minutes each.
It writes the ordinary Application Support database. The normal app build has
no Step 3.1 hooks.

After the long run and a final ordinary `app/build.sh`, `run-app-crash.py`
launches only its own normal app PIDs. Each time it waits for a committed batch,
allows several more uncommitted ticks, sends SIGKILL, checks recovery and
integrity, then starts a second run to prove appending. `measure_release.py`
gives a separate 90-second ordinary-build comparison with the earlier Step 3.1
release sample; it sends SIGTERM to its own PID at the end.

## Minimal Monitor v0.1 checks

Build the ordinary app with `sh app/build.sh`. Run `sh tests/run-checks.sh` and
`python3 tests/run-history-checks.py` for the established collector and logger
checks. `python3 tests/run-migration-checks.py` creates a genuine v1 database
using the frozen `78e2fb2` source, then validates v1→v4, v2 backup→v4,
and the backed-up v3→v4 against the production logger. It verifies original telemetry rows, integrity,
new append behavior, and preservation of the unused legacy v2 table. A missing
core table is rejected without changing `user_version`. The v2/v3 tests need
the local pre-v3/pre-v4 SQLite backups under `backups/`; this directory is Git-ignored.
`python3 tests/verify-real-db.py` compares every original row in both backups
against the current real v4 database without writing to it.

`sh tests/run-localization-checks.sh` checks system-language defaults, both
translation resources, quality labels, immediate switching, and preferences
across three separate processes. Run it in an ordinary-user shell with access
to macOS preferences; the Codex filesystem sandbox can prevent `UserDefaults`
from persisting across processes. `sh app/ui-smoke.sh` verifies both languages
in an AppKit popover, live telemetry, five menu choices, dynamic status-item
width, and layout bounds. It needs an ordinary graphical user session.

With the ordinary app already launched, `python3 tests/run-minimal-regression.py`
observes one PID for 900 seconds at 30-second intervals. It records CPU, RSS,
SQLite counts, integrity, child processes, and network sockets in
`docs/results/minimal-v01-regression.jsonl`. The v3 trace is saved as
`docs/results/minimal-v01-pre-network-regression.jsonl`. The observer never polls hardware
or changes the app's collector or database writer.

`sh tests/run-popover-layout.sh` instantiates only the popover in a separate
AppKit test bundle, without starting the collector or logger. It verifies that
all control bounds fit in the 740-point popover for both supported languages.

`sh tests/run-network-checks.sh` exercises native interface filtering, separate
RX/TX deltas, aggregation, zero, reset, appearance/disappearance, link changes,
and stale windows. It also reads real host interface counters twice without
creating test traffic. `python3 tests/run-network-ab.py` runs the same ordinary
binary for 10 minutes with the Network sampler disabled and 15 minutes enabled;
it uses external libproc and read-only SQLite queries. Network quality and
fast-sample cadence are recorded in `docs/results/network-ab.json`. The
ordinary binary has no sampling-latency probe, so the A/B report labels that
measurement unavailable rather than treating cadence as latency. Energy Impact
and wakeups are also unavailable; context switches are recorded separately.

`sh tests/run-network-benchmark.sh` performs 100 native interface-counter reads
and reports sampler mean, median, and 95th-percentile time. Run it after the
long A/B measurement to avoid contaminating the app CPU comparison.

`sh tests/run-network-latency.sh` is a supplemental review-only timing check:
it runs 60 collector ticks per phase through the production sampling path,
first disabled and then enabled. Its timing excludes AppKit and SQLite work,
so it is kept separate from the 10/15-minute ordinary-binary CPU/RSS A/B.
