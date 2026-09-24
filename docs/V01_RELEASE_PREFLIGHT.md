# v0.1.0 release preflight — 2026-09-24

**Decision state: READY FOR RELEASE DECISIONS.** This is a technical preflight, not a signed, notarized, packaged, or published release. The product scope remains Monitor + Menu Bar + Local SQLite History. No Step 2 or Step 2.6 experiment provenance was changed.

## A. Current Git state

- Checkout: `~/Documents/ChatGPT/MAC性能压榨助手`; branch `phase3/minimal-monitor-v0.1`.
- Starting working tree: clean. Starting HEAD: `3b49558` (`docs: prepare bilingual v0.1 release materials`). The immediately preceding UI and Network commits are `1a06874` and `99a2999`. There is no configured Git remote (`git remote -v` printed nothing).
- This report is the only tracked change in this preflight. No tag, push, release, or repository setting change was made.

## B–D. Product identity, version, and bundle ID

| Key | Current production value | Release assessment |
| --- | --- | --- |
| Product name / `CFBundleName` | `Compute Monitor` | **PRODUCT NAME DECISION REQUIRED:** confirm this as the final public name. |
| Executable / `CFBundleExecutable` | `ComputeMonitor` | Consistent with the build; no decision needed unless the product name changes. |
| `CFBundleDisplayName` | absent | Finder falls back to bundle name; decide whether the final name needs an explicit display key after confirming the name. |
| `CFBundleIdentifier` | `local.compute-monitor` | **BUNDLE ID DECISION REQUIRED:** `local.*` is a development identity. Do not use it for the first public Developer ID release. |
| `CFBundleShortVersionString` | `0.1.0` | Matches the intended `v0.1.0` tag and both READMEs. |
| `CFBundleVersion` | `1` | Suitable first build number. |

No `test`, `dev`, `telemetry-probe`, `example`, or other temporary marker is in the production bundle identity. The only placeholder is `local.compute-monitor`. Once a public bundle ID is used for Developer ID signing, `SMAppService` login registration, and `UserDefaults`, changing it can break continuity; select it before distribution. The data folder is currently named `Compute Monitor`, so a product rename also needs a data-location/migration decision rather than a blind string replacement.

The app is arm64 only (`lipo` and `file`); its Mach-O minimum version and `LSMinimumSystemVersion` are macOS 13.0. `LSUIElement=true` and the app sets AppKit activation policy to `.accessory`, matching its menu-bar-only design. There is no App Sandbox entitlement. App Sandbox and Hardened Runtime are separate controls: the former restricts resources/telemetry and is intentionally absent, while the latter is a code-signing runtime protection needed for notarization.

## E. Signing identities

Read-only `security find-identity -v -p codesigning` returned **0 valid identities**. Identity names, hashes, private keys, and credentials are not recorded here.

| Identity type | Current host |
| --- | --- |
| Developer ID Application | unavailable |
| Apple Development | unavailable |

This is a host readiness fact, not proof that the developer account lacks certificates. An eligible Developer ID Application identity must be available to the later distribution-signing environment.

## F–G. Hardened Runtime and entitlements

The normal `sh app/build.sh` Release-style optimized build completed. Its bundle has only a linker-generated ad-hoc executable signature; `codesign --verify --strict` rejects the unsealed `.app` resources. The production build script has no `--options runtime`, Developer ID signature, secure timestamp, or entitlements file. Therefore its normal output is **not** a distribution candidate.

For this preflight only, an isolated copy under `/private/tmp` was ad-hoc signed with `codesign --force --sign - --options runtime`. `codesign --verify --strict` passed; the signature flags showed `adhoc,runtime`, with no Team ID. In the ordinary local user session, a similarly hardened two-tick telemetry probe reported GPU/IOReport measured, GPU power estimated, AppleSMC measured, Mach CPU measured, and Network RX/TX measured after the initial counter baseline. The hardened production App stayed alive for 40 seconds with `CFFIXED_USER_HOME` redirecting its preferences and database to temporary storage. Its SQLite v4 database passed `PRAGMA quick_check`; 15 fast and 5 slow rows were committed. Latest fast quality was measured for CPU, GPU, Network RX and TX; latest slow quality was estimated for GPU power and measured for both temperatures. This is local ad-hoc runtime evidence, **not** Developer ID, Gatekeeper, notarization, Launch at Login, or future-OS validation. The bounded test process was terminated after inspection, so it did not test the UI Quit path. A first attempt inside the Codex sandbox exited before telemetry could be evaluated, and a sandboxed probe lacked IOReport/AppleSMC access; those sandbox results were not treated as Hardened Runtime failures.

The source loads `/usr/lib/libIOReport.dylib` through `dlopen`/`dlsym`; the successful hardened probe is evidence that this system-library path worked on the tested host. No third-party plug-in or bundled dylib is present. Production entitlements: **none** (`codesign -d --entitlements -` emitted no entitlement dictionary; no `.entitlements` file or `--entitlements` flag exists). There is consequently no entitlement to justify, retain, or delete. The local hardened checks did not require `disable-library-validation`, `allow-jit`, `get-task-allow`, or a network-client entitlement. Network telemetry reads interface counters and initiates no request; no network-client entitlement is indicated. Do not add an exception unless a later signed-candidate failure establishes a concrete need.

Apple's [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) call for Developer ID signing, Hardened Runtime, and a secure timestamp for new direct-distribution code. The project is technically aligned with that route, subject to identity availability and validation of the actual Developer ID candidate. Its lack of App Sandbox does not, by itself, rule out direct distribution.

## H. Launch at Login readiness

Implementation uses `SMAppService.mainApp` on macOS 13+: the checkbox calls `register()` and `unregister()`, rereads `status`, and refreshes on popover open. `.enabled` and `.requiresApproval` display checked; `.notRegistered` displays unchecked; `.notFound` disables the control. Register/unregister errors show localized failure text and are logged. Both languages have the corresponding strings. The UI smoke recorded in `docs/V01_POLISH_REPORT.md` checked state mapping, labels, and callback without changing login items. Apple's [SMAppService documentation](https://developer.apple.com/documentation/servicemanagement/smappservice) supports this API for macOS 13+, and [register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29) describes launching the main app at later logins subject to approval.

A. **Implementation correctness:** source and UI mapping checks support the control path; no source defect was found.
B. **Development-signing limitation:** the normal app bundle has no sealed signature or Team ID, and the earlier ad-hoc UI smoke returned `.notFound`. That cannot establish registration or system approval.
C. **Developer ID verification:** with the final bundle ID and signed/stapled candidate installed at a stable location, inspect initial status, enable the checkbox, approve it in System Settings if required, verify `.enabled`, log out/in and confirm one launch, then disable and confirm `.notRegistered` and no launch on a later login. Test error/revoked-approval state and both languages. Do not substitute LaunchAgent, shell command, or daemon code.

## I. Notarization tooling

`xcrun --find notarytool`, `xcrun --find stapler`, `xcrun --find codesign`, and `xcrun --find spctl` all succeeded; `xcrun notarytool --help` ran. The selected developer directory is Command Line Tools. A notarytool credential profile is **unconfirmed**; no profile or Keychain credential was read. No notarization request was submitted.

## J. Production bundle audit

`app/ComputeMonitor.app` contains one arm64 main executable, `Info.plist`, and `en.lproj` / `zh-Hans.lproj` `Localizable.strings`. `otool -L` shows Apple system frameworks and libraries, including AppKit, IOKit, ServiceManagement, Swift runtime, and `/usr/lib/libsqlite3.dylib`; there are no embedded frameworks, dylibs, helper tools, or bundled SQLite library. No dSYM or debug-symbol bundle is inside the app. The explicit `build.sh` copy list excludes `backups/`, `experiments/`, `docs/results/`, test fixtures, raw traces, and user/backup databases; `find` confirmed none in the built bundle. A marker scan of the executable found no `/Users/`, `/private/tmp/`, experiment, probe, private-key, or common GitHub-token markers. This bounded scan is not a general secret audit. Build output currently lives in the repository but is Git-ignored.

## K. Apple Silicon and private-interface risk

The full telemetry App directly uses the private/undocumented IOReport interface and AppleSMC service. These are retained as the known product tradeoff, not assumed to have an Apple compatibility guarantee. The documented tested hardware is **Apple M1 Max** on **macOS 27.0, build 26A428**; this preflight ran on macOS 27.0 build 26A428 and arm64, while the hardware test claim comes from the existing verification report. Other Apple Silicon hardware and later macOS releases are best effort. Direct distribution is partly chosen because the tested App Sandbox blocked IOReport and AppleSMC access. No x86_64 build was added.

## L. Bilingual README audit

`README.md` and `README.zh-CN.md` have working top links (`English | 简体中文`) and matching coverage of product description, CPU/GPU/temperature/GPU power/Network, SQLite history and growth, English/Chinese UI, privacy, M1 Max/macOS scope, installation status, source build command, local database path, and private-API risk. Their linked local files exist. Both clearly say no public signed/notarized download exists. No factual or translation correction was necessary. After release decisions and actual publication, update both installation sections together with the real asset name and steps; do not preannounce an artifact now.

## M. LICENSE status

**LICENSE DECISION REQUIRED.** There is no `LICENSE` file; the READMEs state that no open-source license is currently granted. If the owner's aim is broad use, modification, and forks while retaining copyright notice and disclaimer, MIT is a common candidate. This preflight does not choose or create a license.

## N. Packaging recommendation

| Option | Installation / GitHub experience | Signing, notarization, and maintenance |
| --- | --- | --- |
| A. Notarized ZIP containing `.app` | Small, direct GitHub download; user unzips and moves the app to Applications manually. | Simple archive creation, but a ZIP cannot itself be signed or stapled. Submit ZIP, staple the contained app, then create the final ZIP containing that stapled app; test the final archive. |
| B. Notarized DMG | Familiar Finder volume; can include an Applications alias for clear drag-to-install guidance. | More layout work, but Apple `hdiutil` and `ditto` suffice. Sign the app and DMG, notarize the DMG, staple the DMG, and verify the exact downloadable file. |

**Recommendation for user decision: B, DMG**, because this menu-bar app benefits from a clear move-to-Applications step before testing Launch at Login. Use Apple's native tools; no third-party DMG builder is needed. ZIP remains a valid simpler choice if the owner prioritizes fewer packaging steps. Apple documents the [container tradeoffs](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) and the [ZIP stapling limitation](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). No package was created.

## O. Proposed GitHub release layout

- Tag: `v0.1.0` (proposal only).
- One arm64 artifact after the packaging decision: `<ConfirmedAppName>-0.1.0-arm64.dmg` **or** `<ConfirmedAppName>-0.1.0-arm64.zip`.
- Optional `SHA256SUMS.txt` for the exact published artifact.
- Draft notes structure: `## English` — lightweight menu-bar CPU/GPU/Temp/GPU Power/NET monitoring; local SQLite history; English/Chinese UI; Apple Silicon/macOS 13+; IOReport/AppleSMC compatibility caveat; install and data path. `## 简体中文` — same facts and limitations in Chinese. State the history-growth estimate as an estimate and the signed Launch at Login result only after it is actually verified.
- No remote is configured, so a later GitHub release task must identify the intended repository before any push or publication.

## P. Signed-candidate release validation checklist

These checks are **pending**, not passed by the local ad-hoc smoke:

- [ ] A. `codesign --verify --deep --strict --verbose=2` on the final installed app; inspect identifier, Team ID, sealed resources, and every nested code item.
- [ ] B. `codesign -dv --verbose=4` shows Hardened Runtime and secure timestamp; confirm minimal entitlements with `codesign -d --entitlements -`.
- [ ] C. `spctl --assess --type execute --verbose=4` accepts the downloaded app after quarantine/Gatekeeper handling.
- [ ] D. `notarytool` result is accepted and its log has no release-blocking issue.
- [ ] E. `stapler validate` passes on the distributed DMG or contained app, as applicable; test offline ticket availability.
- [ ] F. Fresh-copy install and launch from the **exact** final download, preferably on a second clean Mac/account; test both direct/open-in-place and Applications-copy behavior where relevant.
- [ ] G. Menu bar item/popover appear and update.
- [ ] H. CPU, GPU, Temp, GPU Power, and NET show plausible measured/estimated/unavailable states on supported hardware; no private-API loading regression.
- [ ] I. SQLite v4 history is created at the documented path, accrues samples, and passes `PRAGMA quick_check` after Quit.
- [ ] J. English and Simplified Chinese labels, units, and controls are correct.
- [ ] K. Primary metric and language choices persist across relaunch.
- [ ] L. Launch at Login register, approval, enabled state, one login launch, unregister, and disabled state pass in System Settings and UI.
- [ ] M. Quit and relaunch work; clean Quit flushes the writer.
- [ ] N. No Dock icon appears.
- [ ] O. No unexpected outbound network request or App child process is observed during monitoring.
- [ ] P. Existing database survives candidate upgrade/relaunch without losing rows; verify migration and `quick_check`.
- [ ] Q. Confirm the downloaded artifact's SHA-256 matches the published checksum if one is provided.

## Q–R. Exact gates

**User decisions before distribution work:** final Product Name; permanent bundle ID; LICENSE; DMG versus ZIP. The intended GitHub repository/remote also needs to be supplied before a future release task can publish. Any product-name change must account for the existing history directory; any bundle-ID change must be settled before first public signing and login-item registration.

**Developer ID validation before release:** make a valid Developer ID Application identity available; establish a notarytool credential profile without exposing credentials; sign the final-identity bundle with Hardened Runtime and secure timestamp; verify telemetry, SQLite, UI, and `SMAppService` on that exact signed candidate; notarize, staple, Gatekeeper-test, and inspect the final download. The local ad-hoc test cannot close these gates.

## S. Files changed

- `docs/V01_RELEASE_PREFLIGHT.md` only. No application source, test, experiment provenance, README, certificate, Keychain item, package, tag, or remote was changed.

### Frozen performance baseline

The final pre-release 30-minute candidate observation in `docs/V01_POLISH_REPORT.md` remains the baseline: average **0.711% of one CPU core**, peak RSS **81.72 MiB**, and **zero invalid/stale** fast or slow quality entries. This preflight did not optimize performance or claim that its 40-second hardened smoke reproduces those long-run figures.
