#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
clang -O2 -Wall -Wextra -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
  tests/network_checks.m app/NetworkSampler.m -framework Foundation -o .build/network-checks
.build/network-checks
