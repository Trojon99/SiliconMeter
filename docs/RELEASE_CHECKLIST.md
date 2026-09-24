# v0.1.0 release preparation checklist

This is a preparation checklist, not a record of a public release. Do not tag, push, sign, notarize, or publish as part of the local polish stage.

## Product and repository

- [ ] Confirm the final product name **Compute Monitor** and decide whether `local.compute-monitor` is suitable as the distributed bundle identifier.
- [ ] Select and add a LICENSE before a public GitHub release. No open-source license is currently granted.
- [ ] Verify the release commit, clean Git working tree, and `0.1.0` / build `1` in the app bundle and both READMEs.
- [ ] Run the English and Simplified Chinese UI smoke, including all five menu metrics, popover, History, Open Data Folder, Language, Launch at Login, and Quit.
- [ ] Verify SQLite v4 integrity, live recording, UTC/quality semantics, and the documented local data location.

## Distribution build

- [ ] Build the release app from a clean commit with a stable Swift/macOS toolchain.
- [ ] Sign the complete app bundle with an appropriate Apple distribution identity. Confirm bundle ID, hardened runtime where applicable, entitlements, and `LSUIElement` behavior.
- [ ] Verify `SMAppService.mainApp` registration, enabled/disabled/requires-approval states, restart persistence, and the actual macOS Login Items setting in the signed build. The local ad-hoc development bundle reported `notFound`; this is not a signed-release pass.
- [ ] Notarize the distribution artifact and staple the ticket where applicable.
- [ ] Package a DMG or ZIP and verify installation/opening from a fresh location without a Dock icon.
- [ ] Publish a SHA-256 checksum for the exact downloadable artifact.

## Public documentation and release

- [ ] Verify English and Chinese READMEs agree on features, installation, data path, privacy, compatibility, and limits.
- [ ] Recheck that the app generates no monitoring network traffic, collects no user file contents, and has no analytics, cloud upload, or per-process attribution.
- [ ] Keep the M1 Max / macOS 27.0 test scope and IOReport/AppleSMC private-interface risk visible.
- [ ] Prepare concise English release notes and 中文发布说明, including the local-history growth estimate and Launch at Login signing requirement.
- [ ] After all gates pass in a separate release task, create tag `v0.1.0`, push the intended commit/tag, and create the GitHub Release with checksum and notes.
