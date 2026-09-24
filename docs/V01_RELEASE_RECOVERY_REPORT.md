# SiliconMeter v0.1.0 release recovery — 2026-09-24

**Status: NOT RELEASED.** The public history is sanitized locally. The approved App icon PNG is not accessible in this task, so the icon, rebuilt App, and replacement DMG are pending. Do not upload the earlier iconless DMG.

## A. Original blockers

- The original, unpublished release branch contained a user-specific absolute home path in six tracked files across its 25-commit ancestry.
- The prior publication attempt had no GitHub remote, an invalid `gh` login, and no reachable target repository. GitHub CLI authentication has since recovered; the target repository still has not been found.
- A later release requirement adds a formal SiliconMeter App icon, which changes the App bundle and invalidates the earlier DMG as a final release artifact.

## B. History cleanup strategy

Strategy A was used: rewrite only the unpublished release ancestry while retaining all 25 commits, their order, messages, file paths, and technical content. The exact text substitution in affected blobs was a user-specific home prefix to `~/`; this preserves the meaning of local paths without exposing the username. An isolated, independent local clone performed the rewrite. A per-commit comparison confirmed that every changed blob differs only by that substitution.

The original HEAD `83f6788b9287951d1af387a076a2fa0795c1bc8c` remains reachable through the local safety reference `backup/pre-public-release-raw-history`. The sanitized 25-commit ancestry was imported as `public-release/v0.1.0`, and `main` was created from that same tip, initially `05240c611a52db2b37489ed78fd48dbe000aba24`. The safety reference must remain local and must not be included in any public push.

## C. App icon integration

Pending the approved source PNG. The current project builds the App directly with Command Line Tools and has no asset catalog. `actool` is unavailable in this environment; Apple's `iconutil` and `sips` are available for the standard macOS `.iconset` to `.icns` path. No replacement icon has been generated or chosen.

## D. App icon verification

Pending. The image has not been provided as a readable attachment or path in this task. Finder, Applications, and DMG icon checks cannot be claimed.

## E. Privacy audit

The sanitized `main` ancestry contains 25 reachable commits and 271 unique blobs. A bounded scan found no original username, absolute `/Users/<name>/` path, private-key block, GitHub token pattern, or common credential assignment. No database, backup, DMG, certificate, private key, or temporary output filename is tracked. The two remaining `/private/tmp/` mentions are negative examples in audit prose, not private paths. Only `main` and the eventual release tag are intended for GitHub; the raw-history safety reference and other local branches are excluded.

## F. GitHub channel

`gh auth status` now reports a valid Trojon99 login, and `gh api user` returns Trojon99. A query for `Trojon99/SiliconMeter` still reports that the repository cannot be resolved. No remote, tag, push, repository creation, or GitHub Release has been performed. Recheck repository state after the new artifact passes local verification.

## G. New unsigned App verification

Pending the approved icon source and a clean rebuild. The source identity remains SiliconMeter, bundle ID `io.github.trojon99.siliconmeter`, version `0.1.0`, build `1`, and arm64 target. The distribution strategy remains unsigned and not notarized; Launch at Login remains absent.

## H. New DMG

Pending. The existing `release/v0.1.0/SiliconMeter-0.1.0-arm64.dmg` was rechecked with `hdiutil verify` and is intact, but it contains the earlier iconless App and is not the final release asset.

## I. New SHA-256

Pending rebuild. The earlier DMG and `SHA256SUMS.txt` still agree at `0284e97d2d0296fd788a3090bf06a06373a819763c2ef5672850beb0b8da3de2`; this value must not be reused for the new icon-bearing DMG.

## J. Files changed

- Six historical files contain only the home-path substitution in the sanitized ancestry: `docs/V01_IDENTITY_MIGRATION.md`, `docs/V01_RELEASE_PREFLIGHT.md`, `docs/results/v01-polish-matched-new.json`, `docs/results/v01-polish-matched-old.json`, `experiments/results/step26-2026-09-23-summary.json`, and `experiments/results/step26-2026-09-23.jsonl`.
- This report and the supersession notices in `docs/V01_UNSIGNED_RELEASE_CANDIDATE.md` and `docs/RELEASE_CHECKLIST.md` document the current release state.

## K. Commits

The original 25-commit history is preserved by the local safety reference. The sanitized 25-commit history is on `main` and `public-release/v0.1.0`; its original tip before this report was `05240c611a52db2b37489ed78fd48dbe000aba24`. This report's commit is recorded in Git history. No public commit or tag exists yet.

## L. Remaining blockers

The approved App icon PNG must be supplied as a readable attachment or local file. Icon integration, the replacement unsigned App and DMG, a new checksum, local smoke, and final GitHub repository checks follow from that source. Publication remains prohibited until all preconditions pass.
