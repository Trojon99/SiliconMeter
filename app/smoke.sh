#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks app/smoke.m app/TelemetryBackend.m \
  -framework Foundation -framework IOKit -o .build/telemetry-smoke
exec .build/telemetry-smoke "${1:-8}"
