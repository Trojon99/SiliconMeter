# SiliconMeter v0.1.0 GitHub release report — 2026-09-24

**SILICONMETER V0.1.0 RELEASED. MANUAL GATEKEEPER TEST: REQUIRED.**

## A. Repository

[Trojon99/SiliconMeter](https://github.com/Trojon99/SiliconMeter). It was created empty, without a GitHub-generated README, license, `.gitignore`, or extra root commit. Its default branch is `main`, and its description is “A lightweight Apple Silicon telemetry monitor and local history recorder for the macOS menu bar.” The verified topics are `appkit`, `apple-silicon`, `macos`, `menu-bar`, `sqlite`, `swift`, `system-monitor`, and `telemetry`.

## B. Public/private status

Public. Only sanitized `main` and the `v0.1.0` tag were pushed. The raw-history safety branch and other local development branches were not pushed.

## C. main commit

At release publication, GitHub `main` was `f67d7ea554010d16846c36b195ecd40200007ef2`, the verified icon-bearing v0.1.0 source commit. This post-release report and the README updates advance `main` later; they do not alter the release source.

## D. Tag

`v0.1.0` is annotated with message `SiliconMeter v0.1.0`. Its published tag object was `ee28ae8723058f0996cd042eaf33d16b3b7d443a`, peeling to source commit `f67d7ea554010d16846c36b195ecd40200007ef2`. The tag must not be moved.

## E. Release

`SiliconMeter v0.1.0` was published from that tag, with `draft=false` and `prerelease=false`. `docs/V01_RELEASE_NOTES.md` supplied the English and Simplified Chinese notes, including unsigned and non-notarized distribution and the manual **Open Anyway** installation path.

## F. Release URL

[https://github.com/Trojon99/SiliconMeter/releases/tag/v0.1.0](https://github.com/Trojon99/SiliconMeter/releases/tag/v0.1.0)

## G. Artifact

The Release has exactly two uploaded assets: `SiliconMeter-0.1.0-arm64.dmg` (2,602,845 bytes) and `SHA256SUMS.txt` (95 bytes). No database, backup, test file, extra ZIP, or experimental probe was uploaded. GitHub supplies its own source archives.

## H. Published SHA-256

`b921eefb1f06fd12f920460c39ffc1a8be3a56574f6e3e5fbbf3f75b9256724e` for the DMG. GitHub's asset digest, the local checksum file, and the public download all agree. The prior iconless DMG checksum is obsolete and remains only in a Git-ignored local backup.

## I. Public-download SHA-256 verification

Both assets were downloaded through their public HTTPS Release URLs without GitHub credentials. `shasum -a 256 -c SHA256SUMS.txt` passed on those downloaded files. The downloaded DMG was bytewise identical to the final local artifact; the downloaded checksum file matched the local published file as well.

## J. DMG verification

`hdiutil verify` passed on the public-download DMG. It mounted read-only with exactly `SiliconMeter.app` and an `Applications` symlink to `/Applications`. The contained App has bundle ID `io.github.trojon99.siliconmeter`, version `0.1.0`, build `1`, arm64 architecture, `LSUIElement=true`, and `AppIcon.icns`; `codesign --verify --strict` passed for its local ad-hoc resource seal. This is not a Developer ID signature. `NSWorkspace` resolved the supplied custom icon for the App copied from the DMG.

## K. Gatekeeper test

**MANUAL GATEKEEPER TEST REQUIRED.** The anonymous CLI download did not carry `com.apple.quarantine`, so it cannot prove a browser download's first-launch prompt or the **System Settings → Privacy & Security → Open Anyway** flow. Gatekeeper was not disabled and quarantine was not removed to manufacture a pass. The existing installed App and user database were left untouched.

## L. Final smoke

The exact App copied from the public-download DMG stayed alive for 45 seconds in an isolated temporary home. Its new SQLite v4 database passed `quick_check=ok` and recorded 15 fast and 5 slow rows; CPU, GPU, GPU power, Tp05/Tg05 temperature, and network receive/transmit columns all had non-null samples. The isolated process was then terminated. A separate UI smoke from the same source passed all five primary metric choices, English/Chinese, History/retention controls, fixed menu width, accessory/no-Dock mode, and Quit. The **Open Data Folder** control and translation were present; a new Finder click-through was not performed. No long performance benchmark was repeated for this icon-only change.

## M. README bilingual status

Both `README.md` and `README.zh-CN.md` now link the stable GitHub Releases page rather than saying the public download is pending. They state Apple Silicon only, the tested Apple M1 Max/macOS 27.0 build 26A428 environment, unsigned and non-notarized distribution, the manual Gatekeeper path, all five metrics, local SQLite history and retention, English/Chinese, local-only privacy, and MIT licensing.

## N. Remaining limitations

Browser-download Gatekeeper validation and replacement of the existing running `/Applications/SiliconMeter.app` remain manual. IOReport and AppleSMC are private interfaces; other Apple Silicon hardware and macOS versions are best effort. GPU power is estimated. There is no Developer ID signature, notarization, automatic updater, Homebrew Cask, or release automation.

## O. Files changed

Before the tag: six historical files had only a user-specific home-path substitution, `app/Assets.xcassets` added the formal icon sizes, `app/Info.plist` and `app/build.sh` integrated `AppIcon.icns`, and the bilingual READMEs/release notes plus `docs/V01_RELEASE_RECOVERY_REPORT.md` recorded the candidate. The DMG and checksum stayed Git-ignored. After publication: both READMEs, `docs/RELEASE_CHECKLIST.md`, `docs/V01_RELEASE_RECOVERY_REPORT.md`, and this report record the public release.

## P. Commits

The original unpublished 25-commit history is retained locally at `backup/pre-public-release-raw-history`; the public history preserves all 25 commits with only path redaction. The sanitized ancestry entered `main` at `05240c611a52db2b37489ed78fd48dbe000aba24`. `0c6ef5d` documented recovery, `bf7734c` added the icon, and `f67d7ea` verified the unsigned candidate and became the immutable release source. The post-release documentation commit is on `main` after the tag; inspect Git history for its SHA.
