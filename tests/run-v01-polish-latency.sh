#!/bin/sh
# Review-only 60-tick collector latency; never writes history or starts a second app.
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/v01-polish-latency
python3 - <<'PY'
from pathlib import Path
source=Path('app/ComputeMonitor.swift').read_text().split('let app = NSApplication.shared')[0]
Path('.build/v01-polish-latency/main.swift').write_text(
    source+Path('tests/network_latency_fixture.swift').read_text())
PY
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -DSTEP31_REVIEW -fobjc-arc -fblocks \
  -c app/TelemetryBackend.m -o .build/v01-polish-latency/backend.o
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
  -c app/NetworkSampler.m -o .build/v01-polish-latency/network.o
swiftc -O -target arm64-apple-macos13.0 -D STEP31_REVIEW -Xcc -DSTEP31_REVIEW \
  -module-cache-path "$PWD/.build/ModuleCache" -import-objc-header app/TelemetryBackend.h \
  .build/v01-polish-latency/main.swift app/HistoryLogger.swift app/Localization.swift \
  tests/Step31Review.swift .build/v01-polish-latency/backend.o .build/v01-polish-latency/network.o \
  -framework AppKit -framework IOKit -lsqlite3 \
  -o .build/v01-polish-latency/fixture
.build/v01-polish-latency/fixture > docs/results/v01-polish-collector-latency.json
cat docs/results/v01-polish-collector-latency.json
