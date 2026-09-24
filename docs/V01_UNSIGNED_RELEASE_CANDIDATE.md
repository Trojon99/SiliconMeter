# SiliconMeter v0.1.0 unsigned release candidate — 2026-09-24

**Status: READY FOR GITHUB RELEASE PREP.** The local App and DMG candidate passed the checks below. GitHub destination and publication remain pending.

## A. Release strategy

v0.1.0 is an **unsigned, non-notarized open-source community build** for a later public GitHub Release. The bundle has a local ad-hoc resource seal so macOS accepts and opens the complete App; it has no Developer ID identity, Team ID, secure distribution signature, notarization ticket, or Apple verification. Developer ID signing and notarization are future optional improvements. No repository remote, tag, push, or GitHub Release was created here.

## B. Final App identity

| Field | Final candidate |
| --- | --- |
| Product, bundle, display, executable | `SiliconMeter` |
| Bundle ID | `io.github.trojon99.siliconmeter` |
| Version / build | `0.1.0` / `1` |
| Architecture | arm64 only |
| Minimum macOS | 13.0 |
| Menu-bar App | `LSUIElement=true`; AppKit accessory policy |
| License | MIT, `Copyright (c) 2026 Trojon99` |

The clean source commit was `5989b9e` on `release/v0.1-identity`. The first fresh build had only a linker-generated ad-hoc executable signature; `codesign --verify` rejected its unsealed resources and LaunchServices returned `-10827` when opening it. `app/build.sh` now seals the complete bundle ad-hoc after copying resources. A fresh rebuild passed `codesign --verify --strict` and opened from `/Applications`. `codesign -dv` reported `Signature=adhoc`, `TeamIdentifier=not set`, and identifier `io.github.trojon99.siliconmeter`. These are local build properties, not a trusted signature.

## C. Bundle audit

The final bundle contains `Info.plist`, one `SiliconMeter` executable, `en.lproj` and `zh-Hans.lproj` `Localizable.strings`, and `_CodeSignature/CodeResources`. It contains no SQLite database, backup, trace, test fixture, credential, helper, child executable, third-party library, or release test artifact. `otool -L` listed only macOS system frameworks/libraries and the system Swift runtime. A bounded executable string scan found no `/Users/`, `/private/tmp/`, experiment, Headroom, Training Session, or common credential marker. Remaining `training_sessions` source references preserve legacy SQLite foreign keys during retention cleanup; they do not create or expose an experimental feature.

## D–E. Launch at Login decision

The first fresh, sealed, final-identity candidate was installed at `/Applications/SiliconMeter.app`. Its popover showed the localized “当前构建不可用” detail and disabled Launch at Login checkbox. In the then-current code, that combination maps directly and uniquely from `SMAppService.mainApp.status == .notFound`; this was a production UI observation of the property, not an independent instrumented API log.

| Login-item check | Result |
| --- | --- |
| Status before | `.notFound`, via the production UI mapping |
| UI enable / `register()` return or error | Not attempted; the checkbox was disabled by `.notFound` |
| Status after / System Settings item | Not applicable after no registration; no enabled/requires-approval or logout/login result was claimed |

The feature was removed from unsigned v0.1 rather than adding a LaunchAgent or other fallback. Commit `5989b9e` removed its UI, Service Management calls, localization, and related smoke checks. The final candidate has no Launch at Login control or Service Management dependency.

## F–G. DMG and installation verification

`release/v0.1.0/SiliconMeter-0.1.0-arm64.dmg` was created with Apple's `hdiutil` and contains exactly `SiliconMeter.app` plus an `Applications` symlink pointing to `/Applications` for drag installation. `hdiutil verify` passed. The image was mounted read-only; `diff -rq` found no differences between its App and the final build. The contained App passed `codesign --verify --strict`, was copied to a temporary `Applications`-like directory, launched with a live menu-bar metric, and appended SQLite v4 history. The image was unmounted. That exact App was then installed in `/Applications` and launched for the final smoke. No installer package, script, helper, auto-run, notarization, or stapling is present.

## H. Final SHA-256

`release/v0.1.0/SHA256SUMS.txt` was generated after the DMG was finished and `shasum -a 256 -c` passed:

```text
0284e97d2d0296fd788a3090bf06a06373a819763c2ef5672850beb0b8da3de2  SiliconMeter-0.1.0-arm64.dmg
```

The DMG and checksum are Git-ignored local artifacts and are not committed.

## I–J. Public instructions and release notes

`README.md` and `README.zh-CN.md` name the exact DMG, explain drag installation, and state that the build is unsigned and non-notarized. For a blocked first launch, they direct the user to Apple's **System Settings → Privacy & Security → Open Anyway** flow, without Terminal commands or a global Gatekeeper change. `docs/V01_RELEASE_NOTES.md` gives matched English and Chinese features, distribution status, tested environment, and limitations. Source availability is described factually, without treating open source as a safety certification. A locally built App has no browser quarantine, so these checks do not claim that a downloaded copy has passed Gatekeeper end to end.

## K–L. Exact-candidate smoke and performance

The exact App copied from the DMG ran **1,200.17 seconds** under one PID, with 81 observations and no crash. It appended **570 fast** and **190 slow** rows during observation; SQLite stayed at v4 with `quick_check=ok`. Current-run quality counts were measured/estimated/unavailable as expected: fast **3,508 / 585 / 2**, slow **2,533 / 195 / 2**; **invalid=0** and **stale=0** in both. Peak child-process count and open IP socket count were both **0** in the 15-second observations. This is bounded socket observation, not packet capture.

The 20-minute average was **1.025% of one CPU core** and peak RSS was **102.31 MiB**. The frozen earlier reference is **0.711%** and **81.72 MiB**. The 20-minute run included roughly its first half with the popover open and actual UI/Finder interaction, whereas the frozen run measured ordinary background operation. An untouched **120.16-second** relaunch of the same binary measured **0.673% of one core** and **69.88 MiB peak RSS**, with no child process, observed IP socket, crash, invalid/stale quality, or SQLite error. This comparable idle check shows no obvious release-build CPU/RSS regression. The longer interactive peak reflects a different usage state; it is not directly comparable to the frozen idle baseline.

The installed App's real UI showed CPU, GPU, Tp05/Tg05 temperature, estimated GPU power, and NET upload/download. All five primary metric buttons changed the menu-bar label; CPU was restored. English and Simplified Chinese popovers rendered; Chinese was restored. The retention menu offered 1/7/30 days and Forever; the existing Forever preference was retained. Open Data Folder opened Finder at the canonical SiliconMeter Application Support directory. `LSUIElement=true` and the visible session showed a menu-bar item without a Dock icon.

## M. SQLite integrity and retention

Before this step, the existing real database had schema v4, `quick_check=ok`, and 44 app runs / 30,788 fast / 10,291 slow / 86 event rows. Candidate launches added rows without replacing the database. After the 20-minute candidate was asked to Quit normally, it exited, its latest `app_runs.end_utc_ms` was non-null, and the database had **48 app runs / 31,626 fast / 10,573 slow / 94 event rows**, still v4 with `quick_check=ok`. The last batch added another 28 fast rows after the final in-run count. The idle relaunch opened the same database; the real UI still showed **CPU**, **简体中文**, and **永久**. Clicking its **退出** button exited normally with a completed run end time. Final counts were **49 / 31,695 / 10,597 / 96**, with v4 and `quick_check=ok`. No earlier rows were removed; the existing `historyRetentionDays=0` (Forever), `appLanguage=zh-Hans`, and `primaryMetric=0` settings were retained or restored after UI checks. The isolated history and retention suites passed, including flush, reopen, integrity, default and existing-data retention behavior, Cancel/confirm, cleanup, and quality semantics.

## N. Known compatibility limits

The tested machine is Apple M1 Max on macOS 27.0 build 26A428. IOReport and AppleSMC are private interfaces and may change; other Apple Silicon hardware and macOS versions are best effort. GPU power and weighted frequency are estimates. Local build and copy checks do not fully reproduce quarantine and Gatekeeper behavior of a browser download.

## O. GitHub remote

`git remote -v` printed no remote. **GITHUB REMOTE REQUIRED** before any future tag/push/release. `Trojon99/SiliconMeter` is a proposed repository name, not a verified configured destination.

## P–Q. Files changed and commits

- Code commit `5989b9e` (`fix: remove unavailable login-item control from unsigned release`) removes the unsupported feature and makes the normal App/UI-smoke builds resource-sealed with ad-hoc signing. Focused localization, layout, primary-metric persistence, history, and retention checks passed.
- The separate `release: prepare unsigned v0.1 community build` commit contains `.gitignore`, both READMEs, `docs/RELEASE_CHECKLIST.md`, `docs/V01_RELEASE_NOTES.md`, this report, and historical-report supersession notes. Its hash is the Git commit containing this file.
- The DMG, checksum, user database, backups, credentials, and temporary probes remain outside Git.

## R. Remaining publication steps

Review this report and checksum; provide/confirm the GitHub repository and configure its remote. In a separate authorized publication step, create `v0.1.0`, push the reviewed commit/tag, upload the DMG and `SHA256SUMS.txt`, paste the bilingual notes, and verify the uploaded asset's checksum. Replace the READMEs' “public download pending” notice with the actual release link after publication. A fresh browser-download Gatekeeper test on a separate Mac/account remains useful when available. None of these public Git operations were performed in Step 4.4.
