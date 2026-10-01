#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build "app/SiliconMeter.app/Contents/MacOS"
sh app/prepare-sparkle.sh
sparkle="$PWD/.build/dependencies/Sparkle-2.10.0"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks -c app/TelemetryBackend.m -o .build/TelemetryBackend.o
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks -c app/NetworkSampler.m -o .build/NetworkSampler.o
cp app/ComputeMonitor.swift .build/main.swift
swiftc -O -target arm64-apple-macos13.0 -D ENABLE_APP_UPDATES -F "$sparkle" -Xlinker -rpath -Xlinker @executable_path/../Frameworks -module-cache-path "$CLANG_MODULE_CACHE_PATH" -import-objc-header app/TelemetryBackend.h .build/main.swift app/HistoryLogger.swift app/Localization.swift app/IdentityMigration.swift app/UpdateController.swift .build/TelemetryBackend.o .build/NetworkSampler.o \
  -framework AppKit -framework IOKit -framework Sparkle -lsqlite3 -o app/SiliconMeter.app/Contents/MacOS/SiliconMeter
cp app/Info.plist app/SiliconMeter.app/Contents/Info.plist
mkdir -p app/SiliconMeter.app/Contents/Resources
cp -R app/en.lproj app/zh-Hans.lproj app/SiliconMeter.app/Contents/Resources/
rm -rf .build/AppIcon.iconset
mkdir -p .build/AppIcon.iconset
cp app/Assets.xcassets/AppIcon.appiconset/icon_*.png .build/AppIcon.iconset/
iconutil -c icns -o app/SiliconMeter.app/Contents/Resources/AppIcon.icns .build/AppIcon.iconset
mkdir -p app/SiliconMeter.app/Contents/Frameworks
ditto "$sparkle/Sparkle.framework" app/SiliconMeter.app/Contents/Frameworks/Sparkle.framework
cp "$sparkle/LICENSE" app/SiliconMeter.app/Contents/Resources/Sparkle-LICENSE.txt
codesign --force --sign - app/SiliconMeter.app
printf '%s\n' 'Built app/SiliconMeter.app'
