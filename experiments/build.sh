#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p bin
clang -O2 -Wall -Wextra -fobjc-arc -fblocks telemetry_probe.m \
  -framework Foundation -framework IOKit -framework Metal \
  -o bin/telemetry-probe
