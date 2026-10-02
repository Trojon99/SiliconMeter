# SiliconMeter v0.2.0 GitHub release report — 2026-10-02

**SILICONMETER V0.2.0 RELEASED. SIGNED PUBLIC UPDATE FEED VERIFIED.**

## Repository and release

- Public repository: [Trojon99/SiliconMeter](https://github.com/Trojon99/SiliconMeter).
- Release: [SiliconMeter v0.2.0](https://github.com/Trojon99/SiliconMeter/releases/tag/v0.2.0), published `2026-10-02T03:51:37Z`, latest, neither draft nor prerelease.
- Version/build: **0.2.0 / 3**, bundle `io.github.trojon99.siliconmeter`, arm64, macOS 13+.
- Exact release source: `a911244858102d4edce16eeaa95333c1600f2300`.
- Annotated tag object: `1892729de40c3426fee9b2ac4f61a0a8f035d57f`, target `a911244858102d4edce16eeaa95333c1600f2300`.
- Signed-feed publication commit: `36abb1b`. This report is committed afterward; the release tag is not moved.

Existing GitHub documentation commits through `0251d9e` were fetched and merged, including product positioning, Chinese search content, language statistics, visuals and the prior Gatekeeper report. Both READMEs now describe v0.2.0, hardware detection, privacy, first manual installation and subsequent in-app updates. No force push or public-history rewrite was used.

## About and release notes

Repository About was set to:

> Apple Silicon macOS menu bar monitor for CPU, GPU, temperatures, estimated GPU power and network, with local SQLite history and signed in-app updates.

Existing repository topics were preserved. Release notes contain English and Simplified Chinese sections, changes, requirements, installation/upgrade instructions, checksum and verification limits. The published body was compared with `docs/V02_RELEASE_NOTES.md` and matches exactly after trimming trailing whitespace.

## Artifacts and independent downloads

Only these assets were uploaded:

| Asset | Bytes | SHA-256 |
|---|---:|---|
| SiliconMeter-0.2.0-arm64.dmg | 3,282,170 | `c4e91b28caaa636aca33adbf09199a6905cf622756cc2c6b3254bdf3af1bdb50` |
| SHA256SUMS.txt | 95 | `8abc092683e9649a6a224f5e7e1f8ab9258b172a6fdde0e5e7cfa2da1b319668` |

The actual draft download passed checksum and `hdiutil verify` before publication. After publication, both assets were downloaded through public HTTPS URLs without authentication. The public DMG checksum equals the checksum file, the verified local candidate and GitHub's asset digest; its disk-image checksum also passed.

Read-only mounting of that public DMG confirmed the Applications symlink, correct App identity, version/build, arm64 architecture, icon equality and `codesign --verify --deep --strict`. The packaged executable SHA-256 is `ab82122f1e958acb24e4b1d744db66d19a0ef519ab6e4e8caf689ef6aaf88bf0`. Its executable, icon and Info.plist match the production candidate.

## Signed updates

Public feed: [updates/appcast.xml](https://raw.githubusercontent.com/Trojon99/SiliconMeter/main/updates/appcast.xml).

- Feed SHA-256: `40bc77c6fd69f9fa40c78d2fb777924a36dfa1076ba16f74909969903e3f9b86`.
- Enclosure URL references the immutable v0.2.0 DMG asset, with the exact length and archive Ed25519 signature.
- The authorized official Sparkle `sign_update` tool signed the DMG and complete RSS feed with the Keychain key. No private key was exported or tracked. `generate_appcast` waited for a separate Keychain permission and was stopped; see [signing details](V02_UPDATES.md#publication-signing--2026-10-02).
- Both feed and archive signatures verified locally. The anonymous raw feed matches the repository file byte-for-byte and its signature verifies.
- Actual Sparkle checks against the public HTTPS feed passed: build 3 → no update; build 2 → version 3 available. These temporary hosts do not install anything.
- Real loopback Sparkle tests passed six cases: current version, tampered feed, tampered archive, missing feed (404), production-binary installation into a non-running temporary App, and quit/replacement/relaunch of a running harmless AppKit fixture.
- The tampered archive failed EdDSA validation before unarchiving; failed cases preserved the target App. Installation cases verified donor plist, binary/icon, build and code seal. The live fixture's launch marker confirmed the new build and unique bundle identity.

v0.1.0 has no updater. Users must quit it and manually install v0.2.0 once. Later releases require signed assets and a newly signed appcast; pushing source alone does not distribute an update. Download/install remains a user choice; automatic checks are optional and daily. System profile submission is disabled. Metrics and history are not uploaded.

## Smoke and focused verification

Environment: **Apple M1 Max, macOS 27.0 (26A428)**.

| Check | Result |
|---|---|
| Hardware compatibility seams | PASS — 12 layouts, 175 assertions, including M4 Air 4P/6E |
| Backend fault checks | PASS — 101 assertions |
| Metric-service checks | PASS — 48 assertions |
| English/Chinese popover layout and version controls | PASS |
| UI smoke from the release source | PASS — five metrics, fixed width, both languages, History/retention, version/update controls, accessory/no Dock, normal Quit |
| Exact App from anonymous public DMG | PASS — 36-second run in isolated temporary data home |
| Public App history | PASS — SQLite v4, quick_check ok, 15 fast / 5 slow rows; CPU P/E, GPU, temperatures, power and network populated |
| Startup provenance | PASS — 8 performance / 2 efficiency cores, CPU Tp05 and GPU Tg05 |
| Signed-update cases | PASS — six actual Sparkle cases |
| Public HTTPS feed checks | PASS — current/older builds |
| Bounded privacy audit | PASS — unpublished source commits and changed publication text; no home usernames, private-key blocks or token patterns found |

The ordinary public App was terminated after its committed batch was inspected; this does not claim Quit flushing for that run. Normal Quit was exercised by the UI smoke. Installed SiliconMeter and its existing database were not replaced. Raw local logs and generated Apps/DMGs remain Git-ignored. No extended benchmark was repeated.

## Manual acceptance and limitations

- **M4 Air real-device test remains outstanding.** The maintainer authorized publication with this disclosed limitation. Fixtures demonstrate layout handling, not device compatibility. Other chips and macOS versions are best effort; inaccessible metrics stay unavailable.
- **MANUAL GATEKEEPER TEST REQUIRED for v0.2.0.** The previous v0.1.0 browser-download test remains recorded as passed. The new anonymous CLI download does not reproduce browser quarantine/first launch. Use System Settings → Privacy & Security → Open Anyway if blocked; Gatekeeper was not disabled and quarantine was not removed.
- The App has an ad-hoc code seal but no Apple Developer ID identity or notarization. Ed25519 update signing does not replace these.
- Standard update dialogs and the production monitoring App's full update/restart/history-flush lifecycle still need manual acceptance. The live AppKit probe deliberately avoids telemetry and is not the production process.
- Private IOReport/AppleSMC interfaces can change. GPU frequency/power are estimates. Temperature is one selected sensor, not a maximum or average; unavailable startup sensors are not rescanned until restart.

## Prior release preservation

v0.1.0 annotated tag object remains `ee28ae8723058f0996cd042eaf33d16b3b7d443a`, target `f67d7ea554010d16846c36b195ecd40200007ef2`. Its DMG asset digest remains `b921eefb1f06fd12f920460c39ffc1a8be3a56574f6e3e5fbbf3f75b9256724e`; the original assets and release were not replaced. No installed App, user database, backups or private signing material were uploaded.
