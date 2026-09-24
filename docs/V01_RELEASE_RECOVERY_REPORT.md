# SiliconMeter v0.1.0 release recovery — 2026-09-24

**Status: RELEASED.** The public history is sanitized, and the approved App icon is in the rebuilt unsigned App and published DMG. The published download was independently verified. A fresh browser-download Gatekeeper test remains manual-required.

## A. Original blockers

- The original, unpublished release branch contained a user-specific absolute home path in six tracked files across its 25-commit ancestry.
- The prior publication attempt had no GitHub remote, an invalid `gh` login, and no reachable target repository. GitHub CLI authentication has since recovered; the target repository still has not been found.
- A later release requirement adds a formal SiliconMeter App icon, which changes the App bundle and invalidates the earlier DMG as a final release artifact.

## B. History cleanup strategy

Strategy A was used: rewrite only the unpublished release ancestry while retaining all 25 commits, their order, messages, file paths, and technical content. The exact text substitution in affected blobs was a user-specific home prefix to `~/`; this preserves the meaning of local paths without exposing the username. An isolated, independent local clone performed the rewrite. A per-commit comparison confirmed that every changed blob differs only by that substitution.

The original HEAD `83f6788b9287951d1af387a076a2fa0795c1bc8c` remains reachable through the local safety reference `backup/pre-public-release-raw-history`. The sanitized 25-commit ancestry was imported as `public-release/v0.1.0`, and `main` was created from that same tip, initially `05240c611a52db2b37489ed78fd48dbe000aba24`. The safety reference must remain local and must not be included in any public push.

## C. App icon integration

The supplied 1254 × 1254 PNG was the only image source (source SHA-256 `acc98c2ac9a53ebb58318bb2c17c93501a9572cab989f7ef5fcbab6a7dd8ca1`). `sips` generated 16, 32, 64, 128, 256, 512, and 1024 pixel variants in `app/Assets.xcassets/AppIcon.appiconset` with a macOS `Contents.json`. The project builds directly with Command Line Tools, where `actool` is unavailable. The production build copies these variants into a standard `.iconset`, converts it with Apple's `iconutil` to `AppIcon.icns`, places that file in `Contents/Resources`, sets `CFBundleIconFile`, and seals the complete bundle ad-hoc. No custom icon drawing or extra crop was introduced. The original PNG is not embedded separately in the repository; the 1024 pixel catalog image is the retained master variant.

## D. App icon verification

All ten catalog slots have the declared pixel dimensions. `iconutil` accepted the image set in the ordinary user environment; its sandbox-only `Invalid Iconset` result was not a source-asset failure. The compiled `.icns` rendered the supplied design. `NSWorkspace` resolved that custom icon from the built App, the App inside the mounted DMG, a copy installed in a temporary Applications-like directory, and a temporary copy under `/Applications`. The temporary `/Applications` copy was removed after checking. The existing running `/Applications/SiliconMeter.app` and user database were left untouched, so a replacement of that installed copy and a manual Finder Get Info inspection are not claimed.

## E. Privacy audit

Before publication, the sanitized `main` ancestry contained 28 reachable commits and 291 unique blobs. A bounded scan found no original username, absolute `/Users/<name>/` path, private-key block, GitHub token pattern, or common credential assignment, including in the PNG blobs. No database, backup, DMG, certificate, private key, or temporary output filename is tracked. Earlier `/private/tmp/` mentions are negative examples in audit prose, not private paths. Only sanitized `main` and `v0.1.0` were pushed; the raw-history safety reference and other local branches remain local.

## F. GitHub channel

The authenticated Trojon99 account created the empty public `Trojon99/SiliconMeter` repository without GitHub-initialized files. Its default branch is `main`; the About description and eight product topics were verified. `origin` uses a credential-free HTTPS URL. Only sanitized `main` was pushed, at release source commit `f67d7ea554010d16846c36b195ecd40200007ef2`. The annotated `v0.1.0` tag peels to that exact commit. The public non-prerelease GitHub Release is [SiliconMeter v0.1.0](https://github.com/Trojon99/SiliconMeter/releases/tag/v0.1.0).

## G. New unsigned App verification

The clean rebuilt bundle is SiliconMeter, bundle ID `io.github.trojon99.siliconmeter`, version `0.1.0`, build `1`, arm64, `LSUIElement=true`, with `AppIcon.icns` and a valid ad-hoc resource seal. It has no Developer ID signature or notarization; Launch at Login remains absent. An isolated UI smoke passed the five metric choices, English/Chinese content, History/retention controls, fixed menu width, menu-bar accessory state, and Quit. The exact App copied from the new DMG stayed alive for 45 seconds in an isolated temporary home and wrote SQLite v4 history with `quick_check=ok`: 15 fast and 5 slow rows; CPU, GPU, GPU power, Tp05/Tg05, and network receive/transmit fields had non-null samples. The test process was then terminated; this short smoke does not replace the prior long performance run. The Open Data Folder control and translation were checked in the UI smoke; a new click-through Finder test was not performed.

## H. New DMG

The new `release/v0.1.0/SiliconMeter-0.1.0-arm64.dmg` contains the exact rebuilt icon-bearing `SiliconMeter.app` and an `Applications` symlink to `/Applications`. `hdiutil verify` passed on both the staged and final copied DMG. A read-only mount, bytewise App comparison, bundle identity, arm64 architecture, ad-hoc seal, and `NSWorkspace` icon resolution all passed. The old iconless DMG and its checksum were preserved only in Git-ignored `backups/pre-icon-release-20260924/` for local rollback; they must not be uploaded.

## I. New SHA-256

The published DMG SHA-256 is `b921eefb1f06fd12f920460c39ffc1a8be3a56574f6e3e5fbbf3f75b9256724e`. The regenerated local and publicly downloaded `SHA256SUMS.txt` agree; both `shasum -a 256 -c` checks passed. The anonymously downloaded public DMG was bytewise identical to the local final asset, passed `hdiutil verify`, and contained the correct App identity, icon, architecture, and code seal. GitHub's asset digest reports the same SHA-256. The old iconless DMG hash was `0284e97d2d0296fd788a3090bf06a06373a819763c2ef5672850beb0b8da3de2` and must not be listed for the published asset.

## J. Files changed

- Six historical files contain only the home-path substitution in the sanitized ancestry: `docs/V01_IDENTITY_MIGRATION.md`, `docs/V01_RELEASE_PREFLIGHT.md`, `docs/results/v01-polish-matched-new.json`, `docs/results/v01-polish-matched-old.json`, `experiments/results/step26-2026-09-23-summary.json`, and `experiments/results/step26-2026-09-23.jsonl`.
- This report and the supersession notices in `docs/V01_UNSIGNED_RELEASE_CANDIDATE.md` and `docs/RELEASE_CHECKLIST.md` document the current release state.
- `app/Assets.xcassets`, `app/Info.plist`, and `app/build.sh` add the formal icon to the production App. Both READMEs and `docs/V01_RELEASE_NOTES.md` mention the icon. The new DMG and checksum remain Git-ignored.
- After publication, both READMEs link the GitHub Releases page and this report and `docs/RELEASE_CHECKLIST.md` record the public checks. `docs/V01_GITHUB_RELEASE_REPORT.md` is the final publication report.

## K. Commits

The original 25-commit history is preserved by the local safety reference. The sanitized 25-commit ancestry entered `main` at `05240c611a52db2b37489ed78fd48dbe000aba24`; `0c6ef5d` records recovery, `bf7734c` adds the icon, and `f67d7ea` records candidate verification. `v0.1.0` remains on `f67d7ea`; the publication reports and README updates are later commits on `main`, without moving the tag.

## L. Remaining blockers

**MANUAL GATEKEEPER TEST REQUIRED.** The anonymous public CLI download did not have `com.apple.quarantine`, so the real browser-download first-launch warning and **Open Anyway** path were not verified. The existing installed App was left running; the icon-bearing App was checked in a temporary `/Applications` directory and in isolated runtime homes rather than replacing that installation. The public-download exact candidate remained alive for 45 seconds, wrote SQLite v4 history with `quick_check=ok` and non-null samples for all five headline metric groups, then its isolated test process was terminated. No automatic updater, signing, notarization, or extra distribution channel was added.
