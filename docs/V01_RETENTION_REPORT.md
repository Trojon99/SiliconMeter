# SiliconMeter v0.1 — Step 4.2 History Retention report

> Historical retention validation. Step 4.4 changed v0.1.0 to an unsigned, non-notarized community release; Developer ID and notarization are future optional improvements. See [the current candidate report](V01_UNSIGNED_RELEASE_CANDIDATE.md).

Date: 2026-09-24 (Australia/Sydney). Scope: local v0.1 feature freeze before signed release candidate preparation. The pre-feature identity-migration commit was `820a89f` on `release/v0.1-identity`. The telemetry backend was not changed.

## A. Retention model

The History menu offers 1 Day, 7 Days, 30 Days, and Forever. Finite policies use fixed rolling durations of 86,400,000 milliseconds per day on the UTC epoch axis. The deletion predicate is `timestamp < cutoff`; a row exactly at the cutoff is retained. Forever has no age cutoff and logging continues.

## B. Fresh-install default

When `~/Library/Application Support/SiliconMeter/telemetry.sqlite3` does not yet exist and no valid preference exists, the app stores `30` and displays 30 Days / 30 天. The actual AppKit smoke bundle passed twice in a fresh isolated home.

## C. Existing-database migration-safe behavior

When the SQLite file already exists but no valid retention preference exists, the app stores `0` (Forever) before opening the writer. It never guesses from row counts. In an isolated v4 upgrade test, a 100-day-old row survived two AppKit launches. A separate legacy-directory migration moved the v4 database and also preserved its old row under Forever. Canceling a shorter choice preserved the canonical test row; confirming 30 Days removed it on the next launch. The test used distinct test-only bundle IDs because macOS `cfprefsd` can share a standard domain across processes even when `CFFIXED_USER_HOME` differs. The official SiliconMeter preference keys altered by an earlier smoke attempt were removed; the live database file was not modified.

## D. UI

One `NSPopUpButton` sits in the existing History section after Database Size. The popover is 770 points high and passed the English/Chinese control-bounds fixture. A shorter choice shows a modal warning with Cancel first and Delete Old History second. Cancel restores the prior popup selection without writing a preference or scheduling cleanup. A longer choice saves immediately without a confirmation dialog.

## E. Preference storage

`historyRetentionDays` is a local `UserDefaults` integer: 1, 7, 30, or 0 for Forever. `lastRetentionCleanupUTC` is a separate maintenance timestamp. A confirmed shorter selection clears the maintenance timestamp so an interrupted immediate cleanup is retried after relaunch. No retention value is stored in SQLite or in localized text.

## F. Cleanup scheduler

The writer checks once after opening, skips a completed pass if fewer than 24 hours have elapsed, and posts one delayed daily task on its existing serial queue. A confirmed shorter choice requests immediate cleanup on that queue. Sample collection, 2-second rendering, and 6-second slow sampling contain no retention check. The delayed daily task is the only additional scheduled maintenance callback.

## G. Batch deletion strategy

The v4 tables have primary keys but no per-table timestamp indexes. The writer scans primary-key order in 5,000-row pages, deleting only expired rows in a transaction for each page, then queues the next page behind other writer work. This bounds memory and transaction duration while allowing queued telemetry inserts to interleave. It deletes `fast_samples`, `slow_samples`, `events`, and `writer_batches`, then deletes `app_runs` only when the end time (or start time for an unfinished run) is old and no surviving child or legacy `training_sessions` row refers to them. The active run is explicitly excluded. No second writer or schema bump was added.

## H. SQLite and WAL behavior

Schema version remains 4. The existing WAL and synchronous settings are unchanged. Each batch commits or rolls back atomically. No automatic `VACUUM` or aggressive checkpoint was added. The migration fixture passed v1→v4, v2→v4, and v3→v4 with identical core DDL; the history fixture passed WAL read-only access and integrity checks.

## I. 1-day test

Rows at 2 days, 25 hours, and cutoff minus 1 ms were deleted. Rows at the exact cutoff, cutoff plus 1 ms, 23 hours, and now were retained. Three expired rows per time-series table were counted and verified.

## J. 7-day test

Rows at 8 days and cutoff minus 1 ms were deleted. Rows exactly at 7 days and at 6 days were retained. Two expired rows per time-series table were counted and verified.

## K. 30-day test

The 31-day row was deleted. The exactly-30-day and 29-day rows were retained. One expired row per time-series table was counted and verified; no calendar-month calculation is used.

## L. Forever test

A 100-day-old row remained after a forced maintenance request under Forever. Reported age deletions were zero; a newly recorded fast row increased the total by one as expected.

## M. Boundary tests

The fixed-millisecond scenarios explicitly covered cutoff minus 1, exact cutoff, and cutoff plus 1. Each scenario checked `PRAGMA quick_check`, and the full tests also checked `PRAGMA integrity_check` and foreign keys.

## N. Crash-safety test

One process was killed after 100 deletes inside an uncommitted transaction: all 6,000 old fast rows remained and SQLite integrity passed. A restart completed cleanup. Another process was killed after two committed 5,000-row batches: committed rows stayed deleted, later rows remained, and restart finished cleanup while accepting new samples. The legacy `training_sessions` reference test preserved its referenced run; a run ending recently was also preserved after its old child rows were deleted. Unreferenced expired run metadata was removed.

## O. Large-cleanup performance

An isolated v4 database held 40,000 expired rows in each of four time-series tables: 160,000 total. Cleanup deleted all 160,000 in 36 transactions and 37 scan pages. Elapsed time was 1.177 seconds; the longest transaction was 13.013 ms. A 10-ms main-thread heartbeat ran 116 times with a maximum 14.617-ms gap, while fast, slow, and thermal-change event writes interleaved and survived. The fixture child consumed 1.138 CPU seconds and reached 20.5 MiB peak RSS. SQLite integrity and foreign keys passed.

## P. Steady-state overhead

The ordinary optimized app was measured before (`820a89f`) and after retention in separate isolated homes. Each ran 65 seconds, with 25 seconds of warmup and about 38 seconds of stable-window observation. The full result is in `docs/results/retention-steady-comparison.json`.

| Metric, stable window | Before | After |
|---|---:|---:|
| CPU, percent of one core | 0.472% | 0.406% |
| RSS, first → last | 58.42 → 59.92 MiB | 63.09 → 63.45 MiB |
| Median thread count | 6 | 6 |
| Fast / slow rows | 19 / 6 | 19 / 6 |
| Median fast-row gap | 2,103 ms | 2,102 ms |
| Committed writer batches | 2 | 2 |

CPU and recording cadence showed no obvious regression in this short comparison. Post-feature RSS was about 3.53 MiB higher at the window end, but it did not show continuing growth in that window; a longer run would be needed to characterize long-term memory. Source inspection shows one new delayed daily maintenance callback and no added high-frequency timer or collector-path retention check. Ordinary builds do not expose collector function latency, so fast-row cadence is a proxy rather than a direct latency measurement.

## Q. Database-size behavior

After the representative cleanup, the main database file was 25,141,248 bytes and had 6,129 reusable freelist pages. The WAL was 556,232 bytes before closing the writer and absent after close. The Database Size UI still reports main DB + WAL + SHM file bytes. A successful DELETE need not immediately shrink those files; SQLite reuses free pages. No `VACUUM` was run.

## R. Localization

English and Simplified Chinese strings cover the label, all four policies, warning, Cancel, and deletion action. The UI smoke and layout fixture passed both languages. The persisted policy stays numeric across language changes.

## S. Files changed

Production: `app/HistoryLogger.swift`, `app/ComputeMonitor.swift`, and both `Localizable.strings` files. Tests: `tests/retention_fixture.swift`, `tests/run-retention-checks.py`, `tests/run-retention-app-checks.py`, `tests/measure-retention-steady.py`, and `tests/README.md`. Documentation: both READMEs, `docs/HISTORY_SCHEMA.md`, `docs/PRODUCT_SCOPE.md`, `docs/RELEASE_CHECKLIST.md`, this report, and the steady-state result JSON.

## T. Commits

- `257bf9c` — `feat: add configurable history retention` (production implementation and focused tests).
- `f7372ae` — `docs: document history retention and validation` (bilingual docs, checklist, test instructions, measured result).
- `docs: record v0.1 retention preflight` — the local commit containing this report; its own hash is available in `git log` after commit.

## U. Remaining release blockers

History retention has no known functional blocker after the isolated correctness, AppKit, migration, and regression checks. This step did not sign, notarize, staple, package, tag, push, or publish. Developer ID, Hardened Runtime, signed Launch at Login validation, notarization, packaging, and Gatekeeper checks belong to the next release stage.
