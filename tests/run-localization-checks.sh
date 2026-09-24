#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/localization-checks
cp tests/localization_fixture.swift .build/localization-checks/main.swift
swiftc -O -target arm64-apple-macos13.0 -module-cache-path "$PWD/.build/ModuleCache" \
  app/Localization.swift .build/localization-checks/main.swift -o .build/localization-checks/check
.build/localization-checks/check "$PWD/app/SiliconMeter.app"
cp tests/localization_persistence.swift .build/localization-checks/main.swift
swiftc -O -target arm64-apple-macos13.0 -module-cache-path "$PWD/.build/ModuleCache" \
  app/Localization.swift .build/localization-checks/main.swift -o .build/localization-checks/persistence
suite="io.github.trojon99.siliconmeter.localization-restart-$$"
.build/localization-checks/persistence "$PWD/app/SiliconMeter.app" "$suite" write-cn
.build/localization-checks/persistence "$PWD/app/SiliconMeter.app" "$suite" read-cn-write-en
.build/localization-checks/persistence "$PWD/app/SiliconMeter.app" "$suite" read-en-clean
printf '%s\n' 'LOCALIZATION_RESTART PASS English/Chinese/Quit/Restart'
