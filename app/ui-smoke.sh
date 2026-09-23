#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/ComputeMonitorSmoke.app/Contents/MacOS
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks -c app/TelemetryBackend.m -o .build/TelemetryBackend.o
cp app/ComputeMonitor.swift .build/main.swift
swiftc -O -target arm64-apple-macos13.0 -D STEP3_UI_SMOKE -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -import-objc-header app/TelemetryBackend.h .build/main.swift app/HistoryLogger.swift .build/TelemetryBackend.o \
  -framework AppKit -framework IOKit -lsqlite3 \
  -o .build/ComputeMonitorSmoke.app/Contents/MacOS/ComputeMonitor
cp app/Info.plist .build/ComputeMonitorSmoke.app/Contents/Info.plist
exec .build/ComputeMonitorSmoke.app/Contents/MacOS/ComputeMonitor
