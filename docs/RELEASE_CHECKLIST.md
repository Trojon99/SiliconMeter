# v0.1.0 unsigned community release checklist

This is preparation for a public GitHub release. Do not tag, push, or publish until the pending items are complete. Developer ID signing and Apple notarization are future optional distribution improvements, not v0.1 blockers.

## Product and source

- [x] Name `SiliconMeter`, bundle ID `io.github.trojon99.siliconmeter`, version `0.1.0`, build `1`, arm64, macOS 13.0 minimum, and MIT License.
- [x] Product scope remains Monitor + Menu Bar + Local SQLite History; CPU, GPU, Temp, GPU Power, NET, English/简体中文, retention.
- [x] Remove Launch at Login from unsigned v0.1 after the final-identity `/Applications` candidate reported `SMAppService.mainApp.status == .notFound` and disabled its UI control.
- [x] Build from a clean source commit and verify `Info.plist`, architecture, bundle contents, and ad-hoc resource seal. Ad-hoc sealing does not make this a signed/trusted release.
- [x] Verify SQLite v4, retention, bilingual layout, primary-metric persistence, and data continuity.

## Artifact and installation

- [x] Build `SiliconMeter-0.1.0-arm64.dmg` with SiliconMeter.app and an Applications shortcut.
- [x] Integrate the approved SiliconMeter App icon, rebuild the App and DMG, then replace the earlier iconless artifact and checksum. The earlier DMG is not the final release asset.
- [x] Run `hdiutil verify`, mount, compare the contained app byte-for-byte with the final candidate, copy to an Applications-like location, launch, and unmount.
- [x] Confirm the exact DMG app launches from `/Applications` with no Dock icon, five metrics, History, retention, and bilingual UI.
- [x] Complete the 20-minute exact-candidate smoke, including CPU/RSS, SQLite quick_check, no crash, child process, or observed IP socket. An untouched 120-second relaunch showed no obvious idle CPU/RSS regression against the frozen baseline.
- [x] Generate `SHA256SUMS.txt` from the final, unmodified DMG **after** all packaging work; `shasum -a 256 -c` passed.
- [ ] Recheck the published download's SHA-256 against `SHA256SUMS.txt` after upload.

## Documentation and public release

- [x] English and Chinese READMEs describe the unsigned, non-notarized build, data path, compatibility limits, and Apple's manual Gatekeeper **Open Anyway** path.
- [x] Prepare matched English and Chinese release notes in `docs/V01_RELEASE_NOTES.md`.
- [ ] Confirm the intended GitHub repository and configure its remote. No remote is currently configured.
- [ ] Review the final clean commit and artifact checksum, then create the intended `v0.1.0` tag, push, and publish the GitHub Release in a separate authorized step.
- [ ] After publication, replace the READMEs' “public download pending” notice with the actual release link.
- [ ] After publication, verify the actual GitHub download on a fresh Mac/account when available; the local build has no browser quarantine, so this local smoke does not prove the full Gatekeeper download path.
