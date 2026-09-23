# Telemetry history schema v1

## Location and access

The ordinary app writes `~/Library/Application Support/Compute Monitor/telemetry.sqlite3`. The directory is created on first launch. macOS `libsqlite3` is the only database dependency. The app uses WAL and `synchronous=NORMAL`; local SQLite readers can query while recording continues. The `-wal` and `-shm` sidecars are part of an active database. Copy or back up the database using SQLite's backup API rather than copying only the main file while the app runs. There is no network interface, cloud sync, or retention policy.

All `utc_ms` columns and `app_runs.start_utc_ms` / `end_utc_ms` are signed Unix epoch milliseconds in UTC. Local time zone changes do not reinterpret them. `uptime_ms` is the process host's `ProcessInfo.systemUptime` in milliseconds and is meaningful for run-local order and intervals, not as a global timestamp. Individual `*_window_s` columns contain the backend's actual monotonic delta window in seconds where available. Observation timestamps are captured when the central collector publishes its reading; they are not start times for the measurement window. `seq` is the collector tick number. Startup slow sample uses sequence 0; later slow samples share the corresponding fast tick sequence.

`PRAGMA user_version` is **1**. An unknown version is rejected rather than overwritten. The database has one `app_runs` row per launch. `run_id` is a UUID, `end_utc_ms` remains NULL after abnormal termination, `app_version` and `build_version` come from the bundle, `macos_version` from `ProcessInfo`, `macos_build` from `kern.osversion`, `hardware_id` from `hw.model`, `logical_cores` from `ProcessInfo.processorCount`, and `pe_topology_verified` records whether the backend validated the M1 Max P/E mapping. A field containing `unavailable` means the metadata lookup failed; it is not an inferred value.

## Tables and units

| Table | Meaning |
|---|---|
| `fast_samples` | One row per approximately 2 second collector tick. Primary key `(run_id, seq)`. |
| `slow_samples` | One row at startup and every third fast tick, approximately 6 seconds. Primary key `(run_id, seq)`. |
| `events` | Low frequency app start, graceful stop, thermal state change, and memory pressure change. `old_value` and `new_value` are short state labels; no process names or file contents. |
| `writer_batches` | One row per committed sample batch. `fast_rows`, `slow_rows`, and `event_rows` count inserted rows. `duration_ms` measures SQL row insertion time before the batch metadata row and COMMIT; it is a lower bound for the complete transaction, not a disk latency measurement. |

Every sample metric has three columns: `<name>` (REAL or TEXT value), `<name>_quality` (required TEXT), and `<name>_window_s` (nullable REAL seconds). For `unavailable`, `invalid`, or `stale`, the value is NULL. A measured zero remains numeric zero. A missing metric is encoded as NULL with `unavailable`. The five quality states are:

| Quality | Meaning |
|---|---|
| `measured` | Backend supplied a usable measurement or OS state. |
| `estimated` | Usable estimate based on measured counters and assumptions. |
| `unavailable` | No usable reading or baseline exists. |
| `invalid` | A read/counter/state failed validation. |
| `stale` | Backend rejected an excessive or invalid measurement window. |

Fast metrics:

| Column stem | Unit | Meaning |
|---|---|---|
| `cpu_total` | ratio 0–1 | Whole-system logical CPU busy fraction. |
| `cpu_p` | ratio 0–1 | Validated P-core group busy fraction. |
| `cpu_e` | ratio 0–1 | Validated E-core group busy fraction. |
| `gpu_active` | ratio 0–1 | Whole-system GPU active residency fraction. |
| `gpu_frequency_mhz` | MHz | Active-residency-weighted GPU frequency estimate; not an instantaneous clock. |

Slow metrics:

| Column stem | Unit | Meaning |
|---|---|---|
| `gpu_power_w` | W | Estimated GPU power from GPU Energy nJ divided by its actual window. |
| `cpu_tp05_c` | °C | Specific AppleSMC Tp05 sensor. |
| `gpu_tg05_c` | °C | Specific AppleSMC Tg05 sensor. |
| `physical_b`, `free_b`, `active_b`, `inactive_b`, `wired_b`, `compressed_b` | bytes | Physical memory and raw HOST_VM_INFO64 classifications. These are not an estimate of safe available RAM. |
| `swap_used_b` | bytes | `vm.swapusage` used bytes. |
| `swap_in_pages_s`, `swap_out_pages_s` | pages/s | VM swap activity over the actual counter window. |
| `pressure` | text | Current `kern.memorystatus_vm_pressure_level`: Normal, Warning, Critical. |
| `thermal` | text | Current `ProcessInfo.thermalState`: Nominal, Fair, Serious, Critical, Unknown. |

`events.kind` is one of `app_start`, `app_graceful_stop`, `thermal_change`, or `pressure_change`. The first observed state establishes the transition baseline and is saved in `slow_samples`; later changes produce events. Events have their own UTC and uptime times and quality.

## Example SQLite queries

Recent 10 minutes of usable GPU activity, as percentages:

```sql
SELECT datetime(utc_ms/1000, 'unixepoch') AS utc, gpu_active*100 AS gpu_percent,
       gpu_active_quality, gpu_active_window_s
FROM fast_samples
WHERE utc_ms >= (unixepoch('now') - 600)*1000
  AND gpu_active_quality = 'measured'
ORDER BY utc_ms;
```

Average usable P-core activity in a UTC epoch-millisecond interval:

```sql
SELECT run_id, avg(cpu_p)*100 AS avg_p_percent, count(*) AS samples
FROM fast_samples
WHERE utc_ms BETWEEN :start_utc_ms AND :end_utc_ms
  AND cpu_p_quality = 'measured'
GROUP BY run_id;
```

Thermal transitions:

```sql
SELECT datetime(utc_ms/1000, 'unixepoch') AS utc, old_value, new_value
FROM events WHERE kind = 'thermal_change' ORDER BY utc_ms;
```

The schema is directly usable by ordinary SQLite clients and future local analysis code. It contains no high-frequency JSON blob.
