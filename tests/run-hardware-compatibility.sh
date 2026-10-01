#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/hardware-compatibility
clang -O2 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
  tests/hardware_compatibility.m app/NetworkSampler.m -framework Foundation -framework IOKit \
  -o .build/hardware-compatibility/check
.build/hardware-compatibility/check
