#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/PopoverLayout.app/Contents/MacOS .build/PopoverLayout.app/Contents/Resources
python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('app/Info.plist')
d=plistlib.loads(p.read_bytes())
d['CFBundleIdentifier']='io.github.trojon99.siliconmeter.layout-tests'
Path('.build/PopoverLayout.app/Contents/Info.plist').write_bytes(plistlib.dumps(d))
PY
cp -R app/en.lproj app/zh-Hans.lproj .build/PopoverLayout.app/Contents/Resources/
python3 - <<'PY'
from pathlib import Path
source=Path('app/ComputeMonitor.swift').read_text().split('let app = NSApplication.shared')[0]
Path('.build/popover-layout/main.swift').parent.mkdir(parents=True,exist_ok=True)
Path('.build/popover-layout/main.swift').write_text(source+Path('tests/popover_layout_fixture.swift').read_text())
PY
swiftc -O -target arm64-apple-macos13.0 -D STEP3_UI_SMOKE \
  -module-cache-path "$PWD/.build/ModuleCache" -import-objc-header app/TelemetryBackend.h \
  .build/popover-layout/main.swift app/HistoryLogger.swift app/Localization.swift .build/TelemetryBackend.o .build/NetworkSampler.o \
  -framework AppKit -framework IOKit -lsqlite3 \
  -o .build/PopoverLayout.app/Contents/MacOS/SiliconMeter
codesign --force --sign - .build/PopoverLayout.app
.build/PopoverLayout.app/Contents/MacOS/SiliconMeter
