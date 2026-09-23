# Step 3.2 — local telemetry history

This report describes the `phase3/history-logging-v0.1` implementation. Schema details and ordinary SQLite queries are in [HISTORY_SCHEMA.md](HISTORY_SCHEMA.md). Step 3.1 logging-off baseline and its instrumentation caveats are in [STEP31_REVIEW.md](STEP31_REVIEW.md).

## A. SQLite architecture

The existing `TelemetryService` remains the sole owner of Mach, IOReport, AppleSMC and pressure reads. It merges each collector result into the centralized typed `TelemetrySnapshot` on the main queue. `HistoryLogger` consumes those published readings and asynchronously enqueues compact rows on one utility serial writer queue. SQLite open, schema creation, insert, transaction, and close occur only on that writer. No SQLite operation runs on the collector or UI queue during normal sampling. App startup passes the backend's existing P/E topology capability as run metadata. The logger adds no hardware sampler, network operation, model interface, or process attribution.

## B. Schema

Schema version is `PRAGMA user_version=1`. `app_runs` stores UUID, UTC start/end, app/build, OS version/build, hardware model, logical core count and P/E topology validation. `fast_samples` holds the five approximately 2-second CPU/GPU fields; `slow_samples` holds the approximately 6-second power, sensor, VM, swap, pressure and thermal fields. `events` holds app lifecycle and observed state changes. `writer_batches` provides per-batch row counts and precommit SQL insertion duration for overhead review. Numeric unavailable/invalid/stale values are NULL, never zero. Each metric has a quality and actual measurement window where its backend supplies one. See the schema reference for units and examples.

## C. Batching strategy

Fast and slow rows enter in-memory buffers on the writer queue. The existing collector cadence triggers a transaction when at least 30 seconds have passed since the previous flush; no additional high-frequency timer exists. Startup and state-change events share the same batch. Every sample batch uses `BEGIN IMMEDIATE` / `COMMIT`, WAL journal mode, and `synchronous=NORMAL`. A normal AppKit Quit stops collection, queues a graceful-stop event, flushes pending rows, writes the run end time, and closes SQLite. The end-time update is a separate small SQLite statement after the sample batch. A batch transaction failure is logged to stderr and disables recording, so a persistent disk error cannot grow the in-memory buffer without bound.

## D. Crash semantics

An abnormal termination can lose only the current uncommitted memory buffer, with a nominal maximum window of about 30 seconds plus any scheduler delay. Already committed WAL transactions remain readable and recoverable. `synchronous=NORMAL` favors lower disk wakeups over per-sample fsync; it does not promise zero data loss under power failure. An abnormal run has `end_utc_ms=NULL` and no graceful-stop event.

## E. Database location

The database is `~/Library/Application Support/Compute Monitor/telemetry.sqlite3`, with the usual SQLite `-wal` and `-shm` sidecars while open. The app creates the directory when needed using ordinary user permissions. It does not automatically delete or upload history. The operational disk footprint includes main, WAL and SHM files.

## F. Machine-readable access

Read-only `sqlite3` connections may query the live WAL database. The SQLite schema is the machine-readable interface for later local tools; no HTTP, MCP or AI API is present. A new reader can inspect `PRAGMA user_version`, join samples to `app_runs` by `run_id`, filter by UTC epoch milliseconds, and require `measured` or `estimated` quality as appropriate. The controlled functional test kept a read-only connection open while the writer committed a later batch.

## G. Performance result

The isolated `tests/run-history-checks.py` suite passed: new directory/database and schema creation, run metadata, fast/slow/events, `NULL` versus measured zero, UTC epoch milliseconds, estimated quality, graceful flush and end time, reopen/append, WAL read-only query concurrent with a writer, and `integrity_check=ok`. A controlled SIGKILL left one committed fast sample intact, lost only the unflushed second sample, kept `end_utc_ms=NULL`, passed `integrity_check`, and allowed a later run to append. Existing backend fault and typed-snapshot/service checks passed before the long run; a final build/UI smoke follows the long run.

The long run uses the production Swift/Objective-C source under the same `STEP31_REVIEW` observation macro and AppKit driver as the logging-off Step 3.1 baseline. These hooks are absent from the ordinary build. The runner starts the existing Metal GPU workload as a sibling process. It observes SQLite through an external read-only connection approximately every 30 seconds. The 30-minute source and binary hashes are saved in the trace metadata. During that run the user requested a shorter power menu title; a compact title change, an immediate-start event queue-order correction, and a bounded-memory response to transaction failure were made afterward. Their exact source difference is [saved here](results/step32-post-start-fixes.patch); none changes hardware collection, history sampling cadence, SQLite schema, or row binding during successful writes. The final source requires its own functional/UI smoke after the long run. Comparisons with Step 3.1 are indicative, since background OS activity and the source display change can differ between runs.

One App PID ran for 1832 seconds including 30 seconds warmup and approximately 10 minutes each of idle, GPU workload, and recovery. It completed **873 fast ticks**, **292 slow rows** (including startup), **2 lifecycle events**, and **59 committed sample batches**. All 58 running read-only SQLite observations succeeded; final `PRAGMA integrity_check` was `ok`, WAL mode remained active, and the run end timestamp was written. Fast tick numbers were contiguous, slow cadence matched every third tick, all 873 titles matched the central snapshot, and the UI driver made 189 toggles and 172 metric selections. No hardware metric failed or became invalid/stale during the formal phases; the optional `pressureLastEvent` was unavailable because no pressure event occurred. Startup swap rate lacked a baseline for one slow row and was stored as `NULL`/`unavailable`; the remaining 291 were measured.

| Phase | Span | App CPU, % of one core, logging OFF → ON | ON RSS first → last | ON sample latency p95 / max |
|---|---:|---:|---:|---:|
| Idle | 596.3 s | 0.649 → 0.660 | 52.74 → 85.39 MB | 6.34 / 13.42 ms |
| GPU workload | 598.5 s | 0.290 → 0.240 | 85.39 → 85.57 MB | 1.68 / 5.53 ms |
| Recovery | 602.6 s | 0.515 → 0.549 | 85.59 → 85.87 MB | 7.78 / 14.16 ms |

The first UI interaction causes the familiar AppKit RSS step from about 53 to 85 MB. The last two five-minute bins ended at 85.77 and 85.87 MB; observed RSS peak was 86.15 MB and kernel peak RSS 86.31 MB. The logging-off long run ended at 85.67 MB with kernel peak 86.13 MB. No sample-by-sample or late-run runaway RSS trend appeared. The largest formal-phase tick interval was 2.117 s, comparable to the Step 3.1 maximum of 2.116 s. Idle and GPU latency p95 improved versus the baseline (7.03 and 2.17 ms); recovery p95 was 7.78 versus 6.57 ms, while its max was lower (14.16 versus 16.61 ms). The writer's precommit SQL insertion duration averaged **2.15 ms** per approximately 30-second batch and reached **3.81 ms**; this excludes the metadata insert and COMMIT. Ticks immediately after batch timestamps averaged 2.102 s versus 2.100 s for other ticks, a small difference within the normal scheduler jitter; no conspicuous periodic stall appeared. The logging-off and logging-on runs occurred at different times, so their CPU differences are not strict per-component attribution. Disk write bytes and complete wakeup counts were unavailable; OS interrupt/package-idle wakeup categories are present in the JSON summary but are not total wakeups.

The final ordinary app was also tested with a controlled SIGKILL twice: after its first committed batch and about five more seconds, the first run reopened with **15 fast rows and one batch unchanged**, `end_utc_ms=NULL`, WAL mode intact, and `integrity_check=ok`. A second app launch appended under a new run UUID, committed another 15 fast rows, and passed the same post-kill checks. This [app-level crash record](results/step32-app-crash.json) supplements the isolated logger fixture. Final-source UI smoke passed with live CPU/GPU values and verified that representative `Pwr` titles fit within the rendered width of `GPU 100%`.

The uninstrumented ordinary build was measured externally using the same 30-second warmup and approximately 60-second steady interval as the saved Step 3.1 release check. A repeat run without the one-time RSS step used **0.172% of one core**, versus **0.275%** for Step 3.1; RSS was **52.07→52.38 MB**, compared with **51.86→51.89 MB**. The approximately 0.31 MB first-batch rise at 32 seconds then plateaued near 52.35 MB. An initial Step 3.2 short run showed a separate **52→74 MB** step at 22 seconds and then a stable 74.6 MB level; that run did not record popover visibility, so its cause is unproven. The repeat did not reproduce it, and the long-run AppKit-interaction profile remained close to Step 3.1. Neither ordinary run showed a sustained CPU or RSS climb. These short checks use SIGTERM on their own PID and therefore do not test graceful Quit; the long AppKit run, UI smoke, and isolated logger test cover normal flush.

## H. Database growth

The live database peaked at **32,768 B main + 2,401,992 B WAL + 32,768 B SHM = 2,467,528 B** during the run. After graceful exit and checkpoint it occupied **323,584 B main + 0 B WAL + 32,768 B SHM = 356,352 B**. It started at 32,768 B main + 0 B WAL + 32,768 B SHM = 65,536 B; durable observed growth over 0.5086 h was **290,816 B**. This includes a one-time creation of `writer_batches` in the preexisting short development database. The projection below simply scales this observed durable increment and is an order-of-magnitude estimate, not a retention policy or guaranteed long-term slope. WAL is a separate transient operational cost that can reach megabytes while the app runs.

| Duration | Projected durable growth at observed rate |
|---|---:|
| 1 hour | 0.572 MB |
| 24 hours | 13.72 MB |
| 7 days | 96.06 MB |
| 30 days | 411.69 MB |

## I. Remaining limitations

The logger records the existing backend's private API and sensor semantics; it does not improve their calibration or compatibility. Run-local uptime and individual backend windows are available, while the UTC timestamp is the publication time. Per-metric quality is persisted, but backend `source` and `reason` strings are not. No retention, aggregation, sleep/wake event, or long-term size policy is implemented. A device sleep can extend the effective interval until the next collector tick. A persistent disk or schema error leaves recording unavailable and reports to stderr; the menu UI has no recording health indicator yet. The per-batch duration is measured before batch metadata insertion and COMMIT and is therefore a lower bound, not full disk latency. `writer_batches` counts sample batch commits, while run-open/run-end metadata statements are separate.

## J. Recommended next step

After this Step 3.2 gate, use observed growth and failure behavior to choose a local retention/aggregation policy. Keep any future interpretation or model-driven analysis separate from collection and logging.
