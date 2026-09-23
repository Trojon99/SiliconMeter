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
