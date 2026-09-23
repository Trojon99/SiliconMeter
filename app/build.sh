#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build "app/ComputeMonitor.app/Contents/MacOS"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks -c app/TelemetryBackend.m -o .build/TelemetryBackend.o
swiftc -O -target arm64-apple-macos13.0 -module-cache-path "$CLANG_MODULE_CACHE_PATH" -import-objc-header app/TelemetryBackend.h app/ComputeMonitor.swift .build/TelemetryBackend.o \
  -framework AppKit -framework IOKit -o app/ComputeMonitor.app/Contents/MacOS/ComputeMonitor
cp app/Info.plist app/ComputeMonitor.app/Contents/Info.plist
printf '%s\n' 'Built app/ComputeMonitor.app'
