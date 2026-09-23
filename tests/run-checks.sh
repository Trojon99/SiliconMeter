#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/step31-checks
clang -O2 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
  tests/backend_faults.m app/NetworkSampler.m -framework Foundation -framework IOKit -o .build/step31-checks/backend-faults
.build/step31-checks/backend-faults
python3 - <<'PY'
from pathlib import Path
source = Path('app/ComputeMonitor.swift').read_text().split('let app = NSApplication.shared')[0]
Path('.build/step31-checks/main.swift').write_text(source + Path('tests/metric_checks.swift').read_text())
PY
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -DSTEP31_REVIEW -fobjc-arc -fblocks \
  -c app/TelemetryBackend.m -o .build/step31-checks/backend.o
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
  -c app/NetworkSampler.m -o .build/step31-checks/network.o
swiftc -O -target arm64-apple-macos13.0 -D STEP31_REVIEW -Xcc -DSTEP31_REVIEW \
  -module-cache-path "$CLANG_MODULE_CACHE_PATH" -import-objc-header app/TelemetryBackend.h \
  .build/step31-checks/main.swift app/HistoryLogger.swift app/Localization.swift tests/Step31Review.swift .build/step31-checks/backend.o .build/step31-checks/network.o \
  -framework AppKit -framework IOKit -lsqlite3 -o .build/step31-checks/metric-checks
.build/step31-checks/metric-checks
