#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/SiliconMeterSmoke.app/Contents/MacOS
sh app/prepare-sparkle.sh
sparkle="$PWD/.build/dependencies/Sparkle-2.10.0"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks -c app/TelemetryBackend.m -o .build/TelemetryBackend.o
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks -c app/NetworkSampler.m -o .build/NetworkSampler.o
cp app/ComputeMonitor.swift .build/main.swift
swiftc -O -target arm64-apple-macos13.0 -D ENABLE_APP_UPDATES -F "$sparkle" -Xlinker -rpath -Xlinker @executable_path/../Frameworks -D STEP3_UI_SMOKE -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -import-objc-header app/TelemetryBackend.h .build/main.swift app/HistoryLogger.swift app/Localization.swift app/IdentityMigration.swift app/UpdateController.swift .build/TelemetryBackend.o .build/NetworkSampler.o \
  -framework AppKit -framework IOKit -framework Sparkle -lsqlite3 \
  -o .build/SiliconMeterSmoke.app/Contents/MacOS/SiliconMeter
cp app/Info.plist .build/SiliconMeterSmoke.app/Contents/Info.plist
mkdir -p .build/SiliconMeterSmoke.app/Contents/Resources
cp -R app/en.lproj app/zh-Hans.lproj .build/SiliconMeterSmoke.app/Contents/Resources/
mkdir -p .build/SiliconMeterSmoke.app/Contents/Frameworks
ditto "$sparkle/Sparkle.framework" .build/SiliconMeterSmoke.app/Contents/Frameworks/Sparkle.framework
cp "$sparkle/LICENSE" .build/SiliconMeterSmoke.app/Contents/Resources/Sparkle-LICENSE.txt
codesign --force --sign - .build/SiliconMeterSmoke.app
if [ "${1:-}" = "--build-only" ]; then exit 0; fi
exec .build/SiliconMeterSmoke.app/Contents/MacOS/SiliconMeter
