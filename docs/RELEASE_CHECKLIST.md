# v0.1.0 release preparation checklist

This is a preparation checklist, not a record of a public release. Do not tag, push, sign, notarize, or publish as part of the local polish stage.

## Product and repository

- [x] Product name **SiliconMeter**, bundle ID `io.github.trojon99.siliconmeter`, version `0.1.0`, and build `1` are selected. Repository name proposed for the later GitHub release: **SiliconMeter**; no remote is configured yet.
- [x] Add the selected MIT LICENSE with `Copyright (c) 2026 Trojon99`.
- [ ] Verify the final release commit, clean Git working tree, and `0.1.0` / build `1` in the app bundle and both READMEs.
- [ ] Run the English and Simplified Chinese UI smoke, including all five menu metrics, popover, History, Open Data Folder, Language, Launch at Login, and Quit.
- [ ] Verify SQLite v4 integrity, live recording, UTC/quality semantics, and the documented local data location.
- [ ] Verify retention preference persistence and localized 1/7/30-day/Forever choices on the signed candidate.
- [ ] Verify fresh-install default 30 Days and existing-database-without-preference safe default Forever; no silent deletion of old history.
- [ ] Verify destructive shortening confirmation and Cancel semantics, rolling UTC cutoff boundaries, batched cleanup, current-run/FK safety, and no automatic `VACUUM`.

## Distribution build

- [ ] Build the release app from a clean commit with a stable Swift/macOS toolchain.
- [ ] Make a Developer ID Application identity and notarization credentials available, then sign the complete app bundle. Confirm bundle ID, Hardened Runtime, secure timestamp, minimal entitlements, and `LSUIElement` behavior.
- [ ] Verify `SMAppService.mainApp` registration, enabled/disabled/requires-approval states, restart persistence, and the actual macOS Login Items setting in the signed build. The local ad-hoc development bundle reported `notFound`; this is not a signed-release pass.
- [ ] Notarize the distribution artifact and staple the ticket where applicable.
- [ ] Package a DMG or ZIP and verify installation/opening from a fresh location without a Dock icon.
- [ ] Publish a SHA-256 checksum for the exact downloadable artifact.

## Public documentation and release

- [ ] Verify English and Chinese READMEs agree on features, installation, data path, privacy, compatibility, and limits.
- [ ] Recheck that the app generates no monitoring network traffic, collects no user file contents, and has no analytics, cloud upload, or per-process attribution.
- [ ] Keep the M1 Max / macOS 27.0 test scope and IOReport/AppleSMC private-interface risk visible.
- [ ] Prepare concise English release notes and 中文发布说明, including the local-history growth estimate and Launch at Login signing requirement.
- [ ] After all gates pass in a separate release task, configure the intended GitHub remote, create tag `v0.1.0`, push the intended commit/tag, and create the GitHub Release with checksum and notes.
