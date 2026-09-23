# Compute Monitor — Step 3.0

Lightweight native macOS menu-bar system telemetry for the validated Apple M1 Max / macOS 27.0 setup. The production app lives in `app/`; the frozen Step 2/2.6 evidence remains in `experiments/`.

## Build and run

Requires Apple Command Line Tools with Swift and Clang. No package dependencies, root helper, network access, or `powermetrics` are used.

```sh
sh app/build.sh
open app/ComputeMonitor.app
```

The generated app bundle is ignored by Git. It is a **local development build**, not a Developer ID signed or notarized distribution. It has `LSUIElement=true` and runs as an accessory without a Dock icon. It must run outside App Sandbox for IOReport and AppleSMC access. Open the status item to view metrics, choose one of the four primary metrics, or quit. Primary selection is saved with `UserDefaults`; metric history is not saved.

Menu-bar choices: total CPU (`C 23%`), whole-system GPU active ratio (`G 91%`), the selected CPU sensor Tp05 (`72°`), or estimated GPU power (`18W`). `—` means unavailable. The popover labels estimated and unavailable values explicitly.

## Local checks

```sh
sh app/smoke.sh 8
sh app/ui-smoke.sh
```

`smoke.sh` samples the production backend for 16 seconds and prints compact JSON to stdout, including a CPU-time and resident-memory check. `ui-smoke.sh` builds a temporary test variant and programmatically verifies the status item, popover, metric switch, and accessory activation policy. Run these from an ordinary-user macOS session; the Codex shell sandbox can block IOReport, AppleSMC, and sysctl even when the app works normally. Neither check writes metric history.

See [Step 3 architecture](docs/STEP3_ARCHITECTURE.md) for backend boundaries, quality semantics, and distribution risks. Step 2 evidence and reproduction instructions are in [experiments/README.md](experiments/README.md).
