# SiliconMeter v0.2.0 build 3 — version and update controls

Date: 2026-10-02. Status: **SIGNED RELEASE CANDIDATE VERIFIED; PUBLIC FEED PUBLICATION PENDING**.

## User interface

- Title row shows `Current version: 0.2.0` / `当前版本: 0.2.0`, read from the running App's Info.plist. Its tooltip shows build 3.
- Bottom row contains `Check for Updates…` / `检查更新…`, an automatic-check checkbox, and Quit.
- Sparkle controls availability while an update cycle is in progress.
- Automatic checks default to daily. Silent automatic downloading is disabled; downloading/installing is offered through Sparkle's standard UI.
- The current-version value always describes the running App, independently of the latest server version.

## Implementation

Production and UI smoke builds embed Sparkle 2.10.0. The SDK is downloaded to the Git-ignored build cache from the official GitHub asset; the pinned SHA-256 is `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`. `prepare-sparkle.sh` verifies this archive before extraction. The framework is copied with symlinks intact and linked via a bundle-relative runtime path. The upstream license is retained in source and in the App resources.

`UpdateController.swift` uses SPUStandardUpdaterController for checking, compatible version selection, download validation, installation and restart. The popover button closes the popover and brings user-initiated update UI into focus. Automatic reminders use the standard gentle-reminder behavior for an accessory app.

The public Ed25519 key is embedded as SUPublicEDKey. The corresponding private key was generated under Keychain account `io.github.trojon99.siliconmeter` and has not been exported or put in source. Both signed-feed validation and validation before extraction are enabled. The signed update archive is distinct from Apple Developer ID signing; this candidate still lacks Developer ID signing and notarization.

Configured production feed: `https://raw.githubusercontent.com/Trojon99/SiliconMeter/main/updates/appcast.xml`. Before publication it returned HTTP 404. The signed feed is prepared locally; the public publication and download results will be recorded in `V02_GITHUB_RELEASE_REPORT.md`. A failed request remains an update error rather than proof that the App is current.

Update requests fetch version information and release assets. System profile submission is disabled; metrics and history databases do not enter these requests. Sparkle may launch temporary update helpers. No updater is started by telemetry fixture builds, and UI smoke suppresses the scheduled updater to avoid background network requests.

## Verification

- Production arm64 build: PASS.
- English/Chinese popover layout, current-version/build labels and check-button target/action: PASS.
- App UI smoke: PASS for popover, metric selection, fixed width, both languages, version/update controls, History/retention, accessory mode and normal Quit.
- Backend fault checks: PASS, 101 assertions. Metric service checks: PASS, 48 assertions.
- DMG checksum and hdiutil verification: PASS. Read-only mounting confirmed version/build identity, binary and icon equality, and deep code-signature verification of the embedded framework.
- Exact packaged App run: PASS, 36 seconds in a temporary data directory; SQLite v4 quick_check ok, 15 fast and 5 slow committed rows with CPU P/E, GPU, temperature, power and network data. The ordinary App was terminated after checking its committed batch; normal Quit was separately exercised by UI smoke.
- Signed-update checks: **PASS**, six real Sparkle cases: current build, damaged signed feed, damaged archive, missing feed (HTTP 404), replacement of a non-running temporary App with the production binary, and quit/replacement/relaunch of a running harmless AppKit fixture. Signature failures are verified from the Sparkle error domain and underlying validation error. Both installation cases verify build 3, exact donor plist/binary/icon and code seal. The live fixture writes a launch marker with its unique bundle ID/build and does not run telemetry.
- Public update check: **PENDING FEED PUBLICATION** (currently HTTP 404).
- Standard update dialogs, the production monitoring App’s update/restart lifecycle, browser Gatekeeper for this new DMG, and M4 Air: manual acceptance remains required. The harmless live fixture demonstrates Sparkle’s quit/relaunch path; it does not exercise production history flushing during an update.

`tests/run-update-checks.py` performs actual Sparkle checks using a loopback feed and temporary App copies with unique test bundle IDs. The installed App and its user database are not targeted. Signing subprocesses have bounded timeouts. `tests/run-public-update-checks.py` checks the signed publication feed in current-build and older-build hosts without downloading/installing an update.

## Candidate artifact

- `release/v0.2.0/SiliconMeter-0.2.0-arm64.dmg`, version 0.2.0 / build 3.
- Size: 3,282,170 bytes.
- SHA-256: `c4e91b28caaa636aca33adbf09199a6905cf622756cc2c6b3254bdf3af1bdb50`.
- `release/v0.2.0/SHA256SUMS.txt` matches.
- Packaged executable SHA-256: `ab82122f1e958acb24e4b1d744db66d19a0ef519ab6e4e8caf689ef6aaf88bf0`.
- Hardware-only build 2 has been preserved in `release/v0.2.0-build2/` with its original checksum. Published v0.1.0 and its tag have not been changed.

## Maintainer publication workflow

1. Complete signed-update tests and record device/UI acceptance limits. On 2026-10-02 the maintainer explicitly authorized publication with M4 Air real-device verification still outstanding; this is disclosed in both READMEs and release notes.
2. Run `sh app/build.sh`, then `sh app/package.sh` for a new candidate. Existing artifacts are not overwritten; preserve an unpublished candidate before rebuilding, and increase the build number for later updates.
3. Run `sh app/prepare-update.sh`. It checks that the Keychain public key matches the App, copies the DMG/checksum to a separate publication directory, and uses Sparkle's generate_appcast to create and sign `appcast.xml`. Permit the signing tool's Keychain access when macOS asks. The private key remains in the Keychain.
4. Verify the prepared candidate, then publish the matching GitHub Release assets. Copy the generated signed feed into `updates/appcast.xml` and commit/push it only after the assets are available. Do not edit a signed feed after generation; regenerate/sign it if it changes.
5. Download the actual public assets and verify checksums. Fetch the public feed and exercise a real old-to-new update without replacing published tags or release assets.

This repository does not add a GitHub Actions workflow or perform publication automatically. Pushing source alone does not produce a signed update. Older builds need one manual installation of this updater-enabled version before they can discover later updates.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [programmatic integration](https://sparkle-project.org/documentation/programmatic-setup/), [publishing](https://sparkle-project.org/documentation/publishing/).

## Publication signing — 2026-10-02

`sign_update` was granted Keychain access and completed the six test cases. `generate_appcast` separately waited for Keychain authorization; that task-owned process was stopped. The release feed was then constructed as standard RSS from the verified candidate’s version/build/minimum OS and exact archive size, with the immutable Release asset URL. The already authorized official `sign_update` signed the exact DMG and the complete appcast, and verified the appcast signature. No private key was exported. Both the feed and its archive signature are checked again before publication. Future maintainers can use the normal `prepare-update.sh`/`generate_appcast` workflow after granting that tool Keychain access.
