#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/ComputeMonitorReview.app/Contents/MacOS
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -DSTEP31_REVIEW -fobjc-arc -fblocks \
  -c app/TelemetryBackend.m -o .build/ReviewBackend.o
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
  -c app/NetworkSampler.m -o .build/ReviewNetwork.o
cp app/ComputeMonitor.swift .build/main.swift
swiftc -O -target arm64-apple-macos13.0 -D STEP31_REVIEW -Xcc -DSTEP31_REVIEW \
  -module-cache-path "$CLANG_MODULE_CACHE_PATH" -import-objc-header app/TelemetryBackend.h \
  .build/main.swift app/HistoryLogger.swift app/Localization.swift tests/Step31Review.swift .build/ReviewBackend.o .build/ReviewNetwork.o \
  -framework AppKit -framework IOKit -lsqlite3 -o .build/ComputeMonitorReview.app/Contents/MacOS/ComputeMonitor
cp app/Info.plist .build/ComputeMonitorReview.app/Contents/Info.plist
