#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build "app/ComputeMonitor.app/Contents/MacOS"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks -c app/TelemetryBackend.m -o .build/TelemetryBackend.o
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks -c app/NetworkSampler.m -o .build/NetworkSampler.o
cp app/ComputeMonitor.swift .build/main.swift
swiftc -O -target arm64-apple-macos13.0 -module-cache-path "$CLANG_MODULE_CACHE_PATH" -import-objc-header app/TelemetryBackend.h .build/main.swift app/HistoryLogger.swift app/Localization.swift .build/TelemetryBackend.o .build/NetworkSampler.o \
  -framework AppKit -framework IOKit -lsqlite3 -o app/ComputeMonitor.app/Contents/MacOS/ComputeMonitor
cp app/Info.plist app/ComputeMonitor.app/Contents/Info.plist
mkdir -p app/ComputeMonitor.app/Contents/Resources
cp -R app/en.lproj app/zh-Hans.lproj app/ComputeMonitor.app/Contents/Resources/
printf '%s\n' 'Built app/ComputeMonitor.app'
