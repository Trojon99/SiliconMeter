#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/network-latency docs/results
python3 - <<'PY'
from pathlib import Path
source=Path('app/ComputeMonitor.swift').read_text().split('let app = NSApplication.shared')[0]
Path('.build/network-latency/main.swift').write_text(source+Path('tests/network_latency_fixture.swift').read_text())
PY
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -DSTEP31_REVIEW -fobjc-arc -fblocks \
  -c app/TelemetryBackend.m -o .build/network-latency/backend.o
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
  -c app/NetworkSampler.m -o .build/network-latency/network.o
swiftc -O -target arm64-apple-macos13.0 -D STEP31_REVIEW -Xcc -DSTEP31_REVIEW \
  -module-cache-path "$PWD/.build/ModuleCache" -import-objc-header app/TelemetryBackend.h \
  .build/network-latency/main.swift app/HistoryLogger.swift app/Localization.swift \
  tests/Step31Review.swift .build/network-latency/backend.o .build/network-latency/network.o \
  -framework AppKit -framework IOKit -lsqlite3 -o .build/network-latency/fixture
COMPUTE_MONITOR_NETWORK_DISABLED=1 .build/network-latency/fixture > docs/results/network-latency-disabled.json
.build/network-latency/fixture > docs/results/network-latency-enabled.json
cat docs/results/network-latency-disabled.json docs/results/network-latency-enabled.json
