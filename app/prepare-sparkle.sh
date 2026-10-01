#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=2.10.0
checksum=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
directory="$PWD/.build/dependencies/Sparkle-$version"
archive="$directory.tar.xz"
mkdir -p .build/dependencies
if [ ! -f "$archive" ]; then
  curl --fail --location --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 120 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive"
fi
actual=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
if [ "$actual" != "$checksum" ]; then
  printf '%s\n' 'Sparkle SDK checksum mismatch' >&2
  exit 1
fi
if [ ! -d "$directory/Sparkle.framework" ]; then
  mkdir -p "$directory"
  tar -xJf "$archive" -C "$directory"
fi
