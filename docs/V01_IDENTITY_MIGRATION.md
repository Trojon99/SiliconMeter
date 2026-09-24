# v0.1.0 SiliconMeter identity migration — 2026-09-24

**Step 4.1 result: READY FOR SIGNED RELEASE CANDIDATE PREP.** This records a local identity and data-continuity change. It does not record Developer ID signing, notarization, stapling, a DMG/ZIP release package, tag, push, or GitHub Release.

## A–D. Old and new identity, app bundle, and bundle ID

The clean starting point was `a6e44ed` on `phase3/minimal-monitor-v0.1`. Work was done on new branch `release/v0.1-identity`; no remote was configured or added.

| Field | Early development build | Current App |
| --- | --- | --- |
| Product / bundle name | Compute Monitor | **SiliconMeter** |
| Display name | absent | **SiliconMeter** |
| Bundle ID | `local.compute-monitor` | **`io.github.trojon99.siliconmeter`** |
| App bundle | `ComputeMonitor.app` | **`SiliconMeter.app`** |
| Main executable | `ComputeMonitor` | **`SiliconMeter`** |
| Short version / build | `0.1.0` / `1` | **`0.1.0` / `1`** |

`plutil` confirmed every current `Info.plist` value; `file`/`lipo` confirmed arm64 only and `vtool` confirmed macOS 13.0 minimum. `LSUIElement=true` and accessory activation remain. The existing Swift/Objective-C source filenames are internal and were not renamed. The normal build remains ad-hoc linker-signed and is not a distribution-signed App. The only `.app` in `app/` is now the generated `SiliconMeter.app`; the older ignored build was moved into ignored `.build/` after its process exited.

## E. Application Support directory migration

The old code and real environment agreed on `~/Library/Application Support/Compute Monitor/telemetry.sqlite3` with existing `-wal` and `-shm`. The canonical path is now `~/Library/Application Support/SiliconMeter/telemetry.sqlite3`; the SQLite filename is unchanged. `IdentityMigration.prepareForLaunch()` executes once before `AppDelegate` creates its history writer and before the writer opens SQLite. If only the legacy directory exists, the app moves the **whole directory** within the same Application Support parent. This includes main SQLite, WAL, SHM, and any other logger files. If both directories exist, it logs a conflict and uses the canonical directory without changing the legacy directory. If a path is not a directory or the move fails, startup stops before the logger can create an empty replacement database. There is no recurring migration timer or poll. The older app must be quit before the first new-app launch; the real migration followed this rule.

## F. UserDefaults migration

The only persistent user-choice keys found in current source were `appLanguage` (`en` or `zh-Hans`) and `primaryMetric` (raw values 0–4 for CPU, GPU, Temp, GPU Power, NET). On startup the app reads only those validated values from the `local.compute-monitor` suite and copies each only if its new-domain key is absent. Existing new-domain choices win, so repeat launches cannot overwrite later changes. The legacy preferences are retained. Debug/test or unknown keys are not copied. The real development defaults were `zh-Hans` and primary metric `0`; after first new-App launch, `defaults read io.github.trojon99.siliconmeter` showed the same two values. Isolated checks covered both languages, all five metrics, and new-value precedence after modification.

## G. Launch at Login

The implementation still reads `SMAppService.mainApp.status` and calls `register()`/`unregister()` only when the user changes the UI control. No legacy boolean was imported and the new app was not automatically registered. A read-only `sfltool dumpbtm` check, filtered to old/new identities, showed no matching residual login item; that is not a substitute for signed-candidate system validation. The local ad-hoc UI smoke checked both languages and status presentation without changing login registration. Developer ID signing and actual registration, approval, login relaunch, and unregister remain release gates.

## H. SQLite preservation

This is a filesystem identity migration, not a schema migration: `PRAGMA user_version` remains **4**; no table, column, timestamp, historical run, or telemetry backend was rewritten. `fast_samples` retained all six Network columns. The real directory migration preserved the prelaunch baseline of 42 `app_runs`, 30,765 `fast_samples`, 10,282 `slow_samples`, and 82 `events`; the first SiliconMeter run appended rows and passed `PRAGMA integrity_check=ok`. After two graceful new-App runs the counts were 44, 30,788, 10,291, and 86 respectively, with v4 and `integrity_check=ok` still intact. These counts document continuity, not a performance benchmark.

## I–K. Isolated tests: fresh install, legacy, and conflict

`python3 -u tests/run-identity-migration.py` passed all four scenarios in temporary homes, with the AppKit smoke bundle using the new identity and exercising both languages, CPU/GPU/Temp/GPU Power/NET, History, Login UI presentation, fixed menu-bar width, accessory mode, and Quit.

- **A — fresh:** no old directory; SiliconMeter created its canonical v4 database, appended an app run, and passed SQLite integrity and UI smoke.
- **B — legacy:** a SQLite backup API copy of the real v4 schema was given an uncheckpointed but committed WAL row and a separate metadata file. The whole directory moved; all earlier counts survived, the App appended new rows, and a second launch did not repeat migration.
- **C — both directories:** both held real-structure v4 databases and distinct metadata. The legacy directory's file hashes and row counts were unchanged; the canonical database alone received the new run and samples. Both remained SQLite-integrity clean.
- **D — preferences:** isolated domains verified Chinese and English import, all five primary metric values, idempotent new-value precedence, and refusal to import unlisted test/login keys. A non-directory legacy path blocked startup rather than creating a replacement history.

The ordinary `sh app/build.sh` succeeded. Existing focused checks also passed: `tests/run-localization-checks.sh`, `tests/run-primary-metric-persistence.sh`, `tests/run-history-checks.py`, and `tests/run-popover-layout.sh`. No 30-minute performance rerun was needed: the collector and its one timer, 2/6-second cadence, Network backend, menu-bar layout, SQLite v4 writer, non-App-Sandbox design, and minimum architecture/OS were not refactored.

## L. Real development-data migration and backup

The old App process was observed running, then asked to quit normally through its legacy application ID; the process exited before backup. No previous backup was overwritten. A complete copy was made at:

`~/Documents/ChatGPT/MAC性能压榨助手/backups/pre-siliconmeter-identity-20260924T072125Z/Compute Monitor/`

This location is Git-ignored. Its file sizes matched the quiesced source exactly: `telemetry.sqlite3` 11,673,600 bytes, `telemetry.sqlite3-wal` 0 bytes, `telemetry.sqlite3-shm` 32,768 bytes. Both source and copy showed schema v4, `integrity_check=ok`, and the same four core counts: 42 / 30,765 / 10,282 / 82 (app runs / fast / slow / events). The first production `SiliconMeter.app` launch moved the real old directory; the old location then did not exist and the new location did. It ran for 38 seconds, appended history, and quit normally. A 13-second second launch also appended history and quit normally; final counts and integrity are in H. The backup was never bundled, staged, or committed.

## M–N. MIT License and bilingual README

The repository root `LICENSE` contains standard MIT terms with `Copyright (c) 2026 Trojon99`, without extra restrictions. Both READMEs now use **SiliconMeter**, link to each other and the MIT license, show the `SiliconMeter.app` build/open command and canonical data path, and give concise legacy-folder upgrade guidance. `PRODUCT_SCOPE.md`, `HISTORY_SCHEMA.md`, and `RELEASE_CHECKLIST.md` reflect the current name, identity, data path, and decided license. The earlier `V01_RELEASE_PREFLIGHT.md` retains its original historical facts with a prominent decision update pointing here. Step 2/2.6 experiment provenance and earlier test-result reports were not rewritten.

## O–P. Files changed and commits

- App identity/migration: `app/Info.plist`, `app/build.sh`, `app/ComputeMonitor.swift`, `app/HistoryLogger.swift`, `app/IdentityMigration.swift`, both localized `.strings`, and `app/ui-smoke.sh`.
- Tests: new `tests/identity_migration_fixture.swift` and `tests/run-identity-migration.py`; current app/data-path references and test-only bundle IDs updated in relevant scripts; `tests/README.md` documents the migration checks. Historical Step 3 evidence and review-source filenames remain.
- Documentation/license: `LICENSE`, both READMEs, `docs/PRODUCT_SCOPE.md`, `docs/HISTORY_SCHEMA.md`, `docs/RELEASE_CHECKLIST.md`, the historical preflight decision note, and this report.
- Local commits: `bfdc262` (`feat: migrate app identity to SiliconMeter`); `113abbb` (`docs: add MIT license and update release identity`); this report is committed separately. Existing telemetry commits were not squashed.

The built `SiliconMeter.app` contains only `Info.plist`, the arm64 `SiliconMeter` executable, and English/Chinese localization strings. No backups, database, experiment traces, tests, local paths, or credential markers were found in a bounded bundle/content scan. Current Git remote remains empty.

## Q. Remaining release blockers

- A valid **Developer ID Application** signing identity was unavailable at preflight; make one available to the later signing environment.
- Notarization credentials/profile availability is unconfirmed. The signed candidate still needs Hardened Runtime, secure timestamp, code-signature/Gatekeeper checks, and notarization.
- **Launch at Login** must be verified end to end with that final signed candidate and user approval, including login relaunch and unregister.
- Choose and execute the later packaging decision (DMG was recommended at preflight; no package was made here), and verify the exact final artifact.
- Configure the intended **SiliconMeter** GitHub repository/remote only in a later authorized release step. No tag, push, or GitHub Release exists from this step.
