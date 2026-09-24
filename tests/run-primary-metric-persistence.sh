#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/primary-metric-persistence
python3 - <<'PY'
from pathlib import Path
source=Path('app/ComputeMonitor.swift').read_text().split('let app = NSApplication.shared')[0]
Path('.build/primary-metric-persistence/main.swift').write_text(
    source+Path('tests/primary_metric_persistence.swift').read_text())
PY
swiftc -O -target arm64-apple-macos13.0 -module-cache-path "$PWD/.build/ModuleCache" \
  -import-objc-header app/TelemetryBackend.h .build/primary-metric-persistence/main.swift \
  app/HistoryLogger.swift app/Localization.swift .build/TelemetryBackend.o .build/NetworkSampler.o \
  -framework AppKit -framework IOKit -lsqlite3 \
  -o .build/primary-metric-persistence/check
suite="io.github.trojon99.siliconmeter.primary-persistence-$$"
trap '.build/primary-metric-persistence/check "$suite" cleanup' EXIT
for index in 0 1 2 3 4; do
  .build/primary-metric-persistence/check "$suite" write "$index"
  .build/primary-metric-persistence/check "$suite" read "$index"
done
.build/primary-metric-persistence/check "$suite" invalid
printf '%s\n' 'PRIMARY_METRIC_RESTART PASS CPU/GPU/Temp/GPU Power/NET'
