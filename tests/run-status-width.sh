#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/StatusWidth.app/Contents/MacOS .build/StatusWidth.app/Contents/Resources
python3 - <<'PY'
import plistlib
from pathlib import Path
info=plistlib.loads(Path('app/Info.plist').read_bytes())
info['CFBundleIdentifier']='io.github.trojon99.siliconmeter.status-width-tests'
Path('.build/StatusWidth.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
source=Path('app/ComputeMonitor.swift').read_text().split('let app = NSApplication.shared')[0]
Path('.build/StatusWidth.app/Contents/MacOS/main.swift').write_text(source+Path('tests/status_width_fixture.swift').read_text())
PY
cp -R app/en.lproj app/zh-Hans.lproj .build/StatusWidth.app/Contents/Resources/
swiftc -O -target arm64-apple-macos13.0 -module-cache-path "$PWD/.build/ModuleCache" \
  -import-objc-header app/TelemetryBackend.h .build/StatusWidth.app/Contents/MacOS/main.swift \
  app/HistoryLogger.swift app/Localization.swift .build/TelemetryBackend.o .build/NetworkSampler.o \
  -framework AppKit -framework IOKit -lsqlite3 \
  -o .build/StatusWidth.app/Contents/MacOS/StatusWidth
.build/StatusWidth.app/Contents/MacOS/StatusWidth
