# v0.1.0 unsigned community release checklist

SiliconMeter v0.1.0 was published on GitHub on 2026-09-24. The `v0.1.0` tag is immutable; any later fix needs a new version. Developer ID signing and Apple notarization remain future optional distribution improvements.

## Product and source

- [x] Name `SiliconMeter`, bundle ID `io.github.trojon99.siliconmeter`, version `0.1.0`, build `1`, arm64, macOS 13.0 minimum, and MIT License.
- [x] Product scope remains Monitor + Menu Bar + Local SQLite History; CPU, GPU, Temp, GPU Power, NET, English/简体中文, retention.
- [x] Remove Launch at Login from unsigned v0.1 after the final-identity `/Applications` candidate reported `SMAppService.mainApp.status == .notFound` and disabled its UI control.
- [x] Build from a clean source commit and verify `Info.plist`, architecture, bundle contents, and ad-hoc resource seal. Ad-hoc sealing does not make this a signed/trusted release.
- [x] Verify SQLite v4, retention, bilingual layout, primary-metric persistence, and data continuity.

## Artifact and installation

- [x] Build `SiliconMeter-0.1.0-arm64.dmg` with SiliconMeter.app and an Applications shortcut.
- [x] Integrate the approved SiliconMeter App icon, rebuild the App and DMG, then replace the earlier iconless artifact and checksum. The earlier DMG is not the final release asset.
- [x] Run `hdiutil verify`, mount, compare the contained App byte-for-byte with the final icon-bearing candidate, check a temporary `/Applications` copy's icon, and unmount.
- [x] Run the icon-bearing App copied from the DMG in an isolated temporary home; confirm launch, SQLite v4 integrity, and CPU/GPU/temperature/GPU-power/NET history. A separate UI smoke passed five metric choices, History, retention, bilingual UI, accessory mode, and Quit. The existing running `/Applications/SiliconMeter.app` was not replaced.
- [x] Preserve the earlier iconless candidate's 20-minute performance evidence and 120-second idle relaunch as historical comparison; do not claim these durations for the new icon-bearing binary.
- [x] Generate `SHA256SUMS.txt` from the final, unmodified DMG **after** all packaging work; `shasum -a 256 -c` passed.
- [x] Recheck the anonymously downloaded public DMG's SHA-256 against the published `SHA256SUMS.txt`, verify the DMG, and inspect the contained App.

## Documentation and public release

- [x] English and Chinese READMEs describe the unsigned, non-notarized build, data path, compatibility limits, and Apple's manual Gatekeeper **Open Anyway** path.
- [x] Prepare matched English and Chinese release notes in `docs/V01_RELEASE_NOTES.md`.
- [x] Create and verify the public `Trojon99/SiliconMeter` repository and configure `origin`.
- [x] Push only sanitized `main`, create and verify the immutable `v0.1.0` tag, and publish the non-prerelease GitHub Release with two assets.
- [x] Replace both READMEs' pending-download notices with the GitHub Releases page link.
- [ ] Test a fresh browser-downloaded copy's Gatekeeper **Open Anyway** path on a separate Mac/account. The public CLI download had no quarantine attribute, so that full flow remains manual-required.
