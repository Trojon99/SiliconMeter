#!/bin/sh
# Prepare signed publication files locally; uploading remains an explicit release step.
set -eu
cd "$(dirname "$0")/.."
sh app/prepare-sparkle.sh
sdk="$PWD/.build/dependencies/Sparkle-2.10.0"
account=io.github.trojon99.siliconmeter
plist=app/SiliconMeter.app/Contents/Info.plist
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
expected=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")
actual=$("$sdk/bin/generate_keys" --account "$account" -p)
if [ "$actual" != "$expected" ]; then
  printf '%s\n' 'Signing key does not match the public key embedded in this App.' >&2
  exit 1
fi
artifact="$PWD/release/v$version/SiliconMeter-$version-arm64.dmg"
test -f "$artifact"
output="$PWD/.build/update-publication-$version-$build"
if [ -e "$output" ]; then
  printf '%s\n' 'Publication directory already exists; preserve it before preparing another candidate.' >&2
  exit 1
fi
mkdir -p "$output"
cp "$artifact" "$output/"
cp "release/v$version/SHA256SUMS.txt" "$output/"
if [ -f updates/appcast.xml ]; then cp updates/appcast.xml "$output/appcast.xml"; fi
"$sdk/bin/generate_appcast" --account "$account" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/Trojon99/SiliconMeter/releases/download/v$version/" \
  --link 'https://github.com/Trojon99/SiliconMeter/releases' "$output"
"$sdk/bin/sign_update" --account "$account" --verify "$output/appcast.xml"
printf 'Signed publication files: %s\n' "$output"
