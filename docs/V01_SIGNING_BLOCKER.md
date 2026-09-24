# SiliconMeter v0.1.0 — Step 4.3 signing blocker

> Historical record of the earlier Developer ID distribution plan. Step 4.4 changed v0.1.0 to an unsigned, non-notarized community release; Developer ID and notarization are no longer current release blockers. See [the unsigned candidate report](V01_UNSIGNED_RELEASE_CANDIDATE.md).

Date: 2026-09-24 (Australia/Sydney)

## Decision

**BLOCKED: DEVELOPER ID APPLICATION REQUIRED**

The current Keychain has no valid code-signing identity. In particular, **Developer ID Application: UNAVAILABLE**. No signed release candidate can be produced or validated in this state.

## Current evidence

- Repository: `release/v0.1-identity` at `d6b932b`; the working tree was clean before this report was added.
- The identity migration is committed (`bfdc262`, `113abbb`, `820a89f`). The retention implementation and validation are committed (`257bf9c`, `f7372ae`, `d6b932b`).
- `app/Info.plist` specifies `SiliconMeter`, `io.github.trojon99.siliconmeter`, version `0.1.0`, build `1`, `LSUIElement=true`, and macOS 13.0 minimum. `app/build.sh` targets arm64.
- Read-only command: `security find-identity -v -p codesigning`
- Command exit status: `0`; result: `0 valid identities found`.
- Developer ID Application display name and Team ID: unavailable because no valid identity was found.

This is a local Keychain result, not a claim about which certificates exist in the Apple Developer account. Repository source and earlier test reports do not substitute for a current Developer ID signature.

## Required certificate

Apple identifies **Developer ID Application** as the certificate used to sign a Mac app distributed outside the Mac App Store. **Developer ID Installer** is for installer packages and is not the app-signing identity. Apple requires Developer ID signing for this distribution path and describes Hardened Runtime and a secure timestamp in its distribution-signing guidance. See [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates), [Developer ID certificate types](https://developer.apple.com/help/glossary/developer-id-certificate/), and [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/).

Ad-hoc signing has no Developer ID certificate or Team ID. Apple Development or Mac Development certificates identify development builds, not this outside-the-App-Store distribution signature; Apple explicitly excludes ad-hoc and development certificates from the notarization signing requirements. See [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Owner action and resumption gate

Make a valid **Developer ID Application** certificate *with its matching private key* available to code signing in this Mac's Keychain. The Apple Developer team Account Holder can create the certificate in the Apple Developer account or Xcode; if an appropriate certificate already exists, install it through the approved team process. Do not send private keys or credentials in this repository or conversation. Then rerun `security find-identity -v -p codesigning` locally and resume Step 4.3 only when it lists a valid `Developer ID Application: … (TEAMID)` identity.

No new release candidate was built or signed. No notarization, stapling, packaging, install, login-item registration, tag, push, or GitHub Release was performed. The signed-candidate checklist and report remain pending.
