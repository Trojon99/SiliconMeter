# SiliconMeter v0.2.0 compatibility candidate report

Date: 2026-10-01. This report covers hardware candidate build 2, preserved in `release/v0.2.0-build2/` when update candidate build 3 was created. Status: **LOCAL CANDIDATE READY — M4 AIR DEVICE TEST REQUIRED**.

## Identity and source

- Bundle: `io.github.trojon99.siliconmeter`, version `0.2.0`, build `2`, arm64, macOS 13 minimum.
- Source branch: `codex/v0.2.0-hardware-compatibility`.
- Candidate source commit: `be0539984dc7ab8a3db4c64c95806a370c8e5ff4`.
- Existing published `v0.1.0` still points to `f67d7ea554010d16846c36b195ecd40200007ef2`. No published history or tag was changed.
- GitHub release listing read on this date showed only published `v0.1.0`. This task did not push a branch, tag, or Release.
- Community distribution remains unsigned and non-notarized, with only a local ad-hoc code seal.

## Changes and boundaries

The user supplied an M4 Air screenshot with CPU P/E and GPU temperature unavailable. The previous CPU validator restricted the model to M1 Max and hardcoded the first two CPUs as E cores, with 8/2 divisors. It now cross-checks macOS performance-level names and counts against every logical CPU ID and cluster type in IODeviceTree, and calculates the actual group averages. Registry iteration and performance-level order do not determine classification. Invalid, missing, duplicate, or inconsistent metadata keeps group values unavailable; total CPU remains independently sampled. The existing bounded CPU sampler supports up to 64 logical cores.

M1–M4 temperature candidate keys are selected and validated once at startup. M4 GPU candidates include Tg0G/Tg0H and Pro/Max alternatives. Reads retain type, range, and failure checks, and selection skips zero values. UI labels now say CPU/GPU temperature. Each is one selected sensor rather than an aggregate or maximum. Unknown chip temperature mappings remain unavailable. A sensor not available at startup is not rescanned until restart.

GPU activity supports validated OFF/P-state lists of 2–64 states. A missing frequency table affects frequency only; ambiguous tables across multiple dies are rejected. Unsupported channel names or units still fail visibly.

History keeps schema v4 and existing rows. Because older temperature column names contain fixed keys, v0.2.0 adds startup events with the actual selected keys and verified group sizes. Consumers must consult those events for new runs; see [schema notes](HISTORY_SCHEMA.md#v020-sensor-and-topology-provenance).

## Verification

| Check | Result | Evidence and limits |
| --- | --- | --- |
| Deterministic hardware compatibility | PASS | 175 assertions across 12 CPU layouts, including 4P/6E, shuffled rows, reversed levels, non-contiguous grouping, malformed topology, and M1–M4 mocked sensor responses |
| Backend faults | PASS | 101 assertions, including CPU rollback/wrap, SMC failure, variable GPU states, and activity without a frequency table |
| Metric service checks | PASS | 48 assertions |
| Real hardware backend smoke | PASS | M1 Max / macOS 27.0 build 26A428; verified 8P/2E, GPU activity/frequency/power, Tp05/Tg05 temperature and network after baseline |
| App UI smoke | PASS | Separate build from the same source: popover, five metric choices, fixed width, Chinese/English, History/retention UI, accessory mode and normal Quit |
| DMG identity / icon / binary | PASS | Read-only mount; Applications shortcut; temporary install copy; plist 0.2.0/build 2/arm64; code seal verification; binary, icon and plist match the built App |
| Exact packaged App history | PASS | 36-second ordinary App run with a temporary Foundation data home; 15 committed fast rows, 5 slow rows, CPU P/E, GPU, temperatures, power and network present; SQLite v4 quick_check ok |
| Sensor provenance | PASS | Startup events recorded Tp05, Tg05, 8 performance cores and 2 efficiency cores for the M1 Max run |
| Bounded privacy check | PASS | Changed/new tracked source and docs checked for user absolute paths, common token/private-key markers, and accidental binary/database inclusion |
| M4 Air real hardware | REQUIRED | No M4 Air was available in this workspace. Fixtures are not real device validation. User macOS version has not yet been supplied. |
| Browser Gatekeeper first launch | REQUIRED | Local build and temporary installation do not reproduce a real quarantined internet download |

The existing installed App and user history database were not replaced. Temporary data directories were used for both UI and packaged-App checks; shared app preferences can still be read by macOS CFPreferences. The ordinary packaged App was terminated after observing its committed batch; final uncommitted rows are not counted as a successful Quit flush. The UI smoke separately exercised normal Quit. No long performance or physical restart test was run.

The backend smoke observed 0.021254 CPU seconds across about 8.04 seconds and no child process; this short sample is not a battery or long-term overhead benchmark.

## Artifact

- Local DMG: `release/v0.2.0-build2/SiliconMeter-0.2.0-arm64.dmg`.
- Size: 2,671,541 bytes.
- SHA-256: `2826235426ee25b2cb1533f3f0731422435f2d420e1de4932393bcaf3fae39fe`.
- Checksum file: `release/v0.2.0-build2/SHA256SUMS.txt`.
- DMG checksum verification and `hdiutil verify`: PASS.
- Packaged executable SHA-256: `de5ae95b6d6fce3c2ae15bd0b9997f0b31483a4e092546ab119b44224dbabe68`.
- Artifacts remain Git-ignored. Packaging script derives the version from the App and refuses to overwrite existing files. An earlier local candidate was preserved under `.build/` before the provenance-aware final rebuild; it was never published.

## M4 Air acceptance check

1. Quit the old SiliconMeter, then install this DMG's App into Applications and launch it. Use the documented macOS Open Anyway exception if required.
2. Confirm the running App is the new copy; wait at least 6 seconds after startup. CPU total, P-core and E-core should show readings when the device metadata validates. A zero activity value is valid; unavailable is not the expected result for valid M4 4P/6E metadata.
3. Check GPU temperature and the five metric choices in both languages. Temperature may remain unavailable if none of the supported sensors is accessible.
4. Send the macOS version and a new popover screenshot. If grouping remains unavailable, run the source smoke probe on that device to inspect actual counts and selected sensors before changing the mapping again.
5. Confirm existing history remains readable and Quit normally. Public v0.2.0 publication is pending these device results and publication authorization.

## Files changed

`app/TelemetryBackend.m`, `app/ComputeMonitor.swift`, `app/HistoryLogger.swift`, `app/Info.plist`, both localization resources, `app/package.sh`, `tests/backend_faults.m`, the new hardware compatibility fixture and runner, both READMEs, `tests/README.md`, `docs/HISTORY_SCHEMA.md`, and the new v0.2.0 notes/report. Historical v0.1.0 reports remain as release provenance.
