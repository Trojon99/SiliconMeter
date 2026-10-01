#!/bin/sh
# Package the already-built App. Each version has its own immutable local artifact.
set -eu
cd "$(dirname "$0")/.."
bundle="app/SiliconMeter.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")
case "$version" in ''|*[!0-9.]*) printf '%s\n' 'Invalid bundle version' >&2; exit 1;; esac
test "$identifier" = 'io.github.trojon99.siliconmeter'
test "$(lipo -archs "$bundle/Contents/MacOS/SiliconMeter")" = arm64
test -s "$bundle/Contents/Resources/AppIcon.icns"
codesign --verify --deep --strict "$bundle"
output="$PWD/release/v$version"
artifact="SiliconMeter-$version-arm64.dmg"
if [ -e "$output/$artifact" ] || [ -e "$output/SHA256SUMS.txt" ]; then
  printf '%s\n' 'Artifact already exists; choose a new version or preserve the earlier candidate first.' >&2
  exit 1
fi
mkdir -p .build "$output"
stage=$(mktemp -d "$PWD/.build/dmg-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
ditto "$bundle" "$stage/SiliconMeter.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "SiliconMeter $version" -srcfolder "$stage" -fs HFS+ -format UDZO "$output/$artifact"
hdiutil verify "$output/$artifact"
cd "$output"
shasum -a 256 "$artifact" > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
