# Compute Monitor — menu-bar v0.1

Lightweight native macOS menu-bar system telemetry for the validated Apple M1 Max / macOS 27.0 setup. The production app lives in `app/`; the frozen Step 2/2.6 evidence remains in `experiments/`.

## Build and run

Requires Apple Command Line Tools with Swift and Clang. No package dependencies, root helper, network access, or `powermetrics` are used.

```sh
sh app/build.sh
open app/ComputeMonitor.app
```

The generated app bundle is ignored by Git. It is a **local development build**, not a Developer ID signed or notarized distribution. It has `LSUIElement=true` and runs as an accessory without a Dock icon. It must run outside App Sandbox for IOReport and AppleSMC access. Open the status item to view metrics, choose one of the four primary metrics, or quit. Primary selection is saved with `UserDefaults`. Telemetry history is recorded locally in SQLite under Application Support; see [schema and queries](docs/HISTORY_SCHEMA.md).

Menu-bar choices: total CPU (`CPU 23%`), whole-system GPU active ratio (`GPU 91%`), the selected CPU sensor Tp05 (`Temp 61°C`), or estimated GPU power (`Pwr 14W`). `—` means unavailable. The compact power title stays within the width of `GPU 100%` for tested values, with one decimal below 10 W; the popover keeps the precise estimated value. The popover identifies the temperature sensors and labels estimated and unavailable values explicitly.

## Local checks

```sh
sh app/smoke.sh 8
sh app/ui-smoke.sh
```

`smoke.sh` samples the production backend for 16 seconds and prints compact JSON to stdout, including a CPU-time and resident-memory check. `ui-smoke.sh` builds a temporary test variant and programmatically verifies the status item, popover, metric switch, and accessory activation policy. The UI smoke variant uses the production history logger and writes a short run to the normal Application Support database. Run these from an ordinary-user macOS session; the Codex shell sandbox can block IOReport, AppleSMC, and sysctl even when the app works normally.

See [Step 3 architecture](docs/STEP3_ARCHITECTURE.md) for backend boundaries, quality semantics, and distribution risks. Step 2 evidence and reproduction instructions are in [experiments/README.md](experiments/README.md).

## Step 3.1 review

[Independent architecture and stability review](docs/STEP31_REVIEW.md) records
production-path testing, minimal correctness/lifecycle fixes, and remaining
limits. Reproduction tools are in [tests/README.md](tests/README.md); their
compile-time observation hooks are excluded from the ordinary app.

## Step 3.2 history

History records the existing fast and slow telemetry snapshots and state changes without new hardware reads. One background SQLite writer batches samples about every 30 seconds and flushes on a normal Quit. The most recent uncommitted batch may be lost on an abnormal exit. [Schema v1](docs/HISTORY_SCHEMA.md) describes the location, units, quality states, and plain SQLite queries. [Step 3.2 report](docs/STEP32_HISTORY_LOGGING.md) records validation and observed overhead.
