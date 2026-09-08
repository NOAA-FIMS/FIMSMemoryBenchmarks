# FIMS macOS Native Memory Benchmark Report

Generated: `2026-08-25T00:25:08+00:00`
Host: `macOS 15.7.7 (arm64)`
Profilers: Instruments Allocations and `/usr/bin/time -l`

## Summary

macOS reports process-level physical memory rather than Massif's allocated heap. Maximum resident set size (RSS) is the primary comparison metric; peak memory footprint is also shown when the host provides it.

| Git ref | FIMS version | Maximum RSS | Peak footprint | Elapsed | Instruments |
|---|---:|---:|---:|---:|---|
| main | 0.10.0.9000 | **4.96 GiB** | 2.99 GiB | 14.99 s | captured |
| dev-native-quadra | 0.10.0.9000 | **489.28 MiB** | 382.49 MiB | 6.44 s | captured |

## Detailed branch comparison

`dev-native-quadra` used **4.48 GiB less maximum RSS** than `main` (-90.37%).

Positive deltas mean the comparison ref used more of that metric; negative deltas mean less.

| Metric | `main` | `dev-native-quadra` | Delta | Change |
|---|---:|---:|---:|---:|
| Maximum RSS | 4.96 GiB | 489.28 MiB | −4.48 GiB | -90.37% |
| Peak footprint | 2.99 GiB | 382.49 MiB | −2.62 GiB | -87.51% |
| Elapsed time | 14.99 s | 6.44 s | -8.55 s | -57.04% |
| User CPU time | 13.74 s | 6.35 s | -7.39 s | -53.78% |
| System CPU time | 1.08 s | 0.07 s | -1.01 s | -93.52% |
| Page reclaims | 546,868 | 35,203 | -511,665 | -93.56% |
| Page faults | 62 | 24 | -38 | -61.29% |
| Swaps | 0 | 0 | +0 | 0.00% |

### Interpretation

- Maximum RSS decreased by 4.48 GiB (-90.37%), from 4.96 GiB to 489.28 MiB.
- Peak memory footprint decreased by 2.62 GiB (-87.51%), from 2.99 GiB to 382.49 MiB.
- Elapsed time decreased by 8.55 s (-57.04%), from 14.99 s to 6.44 s.
- Page faults decreased by 38 (-61.29%), from 62 to 24.

### Instruments allocation totals

Persistent bytes were still allocated at the end of the recording; transient bytes were allocated and freed during the recorded interval.

| Metric | `main` | `dev-native-quadra` | Delta | Change |
|---|---:|---:|---:|---:|
| Persistent bytes | 2.41 GiB | 219.62 MiB | −2.19 GiB | -91.10% |
| Transient bytes | 18.44 GiB | 632.54 MiB | −17.82 GiB | -96.65% |
| Total recorded bytes | 20.85 GiB | 852.16 MiB | −20.01 GiB | -96.01% |
| Persistent allocations | 62,594 | 46,092 | -16,502 | -26.36% |
| Transient allocations | 1,185,792 | 461,807 | -723,985 | -61.05% |
| Total allocations | 1,248,386 | 507,899 | -740,487 | -59.32% |
| Allocation events | 2,431,891 | 969,622 | -1,462,269 | -60.13% |

- Persistent allocated memory decreased by 2.19 GiB (-91.10%), from 2.41 GiB to 219.62 MiB.
- Transient allocated memory decreased by 17.82 GiB (-96.65%), from 18.44 GiB to 632.54 MiB.
- Allocation events decreased by 1,462,269 (-60.13%), from 2,431,891 to 969,622.

### Largest persistent-allocation category changes

| Category | `main` | `dev-native-quadra` | Delta | Change |
|---|---:|---:|---:|---:|
| VM: MALLOC_LARGE | 5.32 GiB | 165.02 MiB | −5.16 GiB | -96.97% |
| Malloc 512.00 MiB | 1.00 GiB | 0 B | −1.00 GiB | -100.00% |
| Malloc 340.67 MiB | 681.34 MiB | 0 B | −681.34 MiB | -100.00% |
| Malloc 256.00 MiB | 256.00 MiB | 0 B | −256.00 MiB | -100.00% |
| VM: MALLOC_MEDIUM | 640.00 MiB | 384.00 MiB | −256.00 MiB | -40.00% |
| Malloc 182.28 MiB | 182.28 MiB | 0 B | −182.28 MiB | -100.00% |
| Malloc 8.00 KiB | 231.32 MiB | 179.41 MiB | −51.91 MiB | -22.44% |
| VM: MALLOC_SMALL | 264.00 MiB | 216.00 MiB | −48.00 MiB | -18.18% |
| Malloc 2.69 MiB | 8.06 MiB | 0 B | −8.06 MiB | -100.00% |
| Malloc 4.00 MiB | 8.00 MiB | 0 B | −8.00 MiB | -100.00% |

### Persistent allocation origins

Instruments attributes allocations still live at the end of each recording to the most specific exported responsible symbol. Generic C++ allocations in `FIMS.so` are kept separate when the export does not identify the backend.

| Origin | `main` bytes | Share | `dev-native-quadra` bytes | Share |
|---|---:|---:|---:|---:|
| TMB/TMBad | 801.38 MiB | 32.49% | 4.84 KiB | 0.00% |
| Quadra | 0 B | 0.00% | 2.52 KiB | 0.00% |
| Rcpp | 204.03 KiB | 0.01% | 0 B | 0.00% |
| R runtime | 236.50 MiB | 9.59% | 175.72 MiB | 80.01% |
| FIMS C++ (backend not explicit) | 1.35 GiB | 56.07% | 39.67 KiB | 0.02% |
| System/other/unresolved | 45.46 MiB | 1.84% | 43.85 MiB | 19.96% |

## Run details

### `main` (FIMS 0.10.0.9000)

| Metric | Value |
|---|---:|
| Maximum resident set size | 4.96 GiB |
| Peak memory footprint | 2.99 GiB |
| Elapsed time | 14.99 s |
| User CPU time | 13.74 s |
| System CPU time | 1.08 s |
| Page reclaims | 546,868 |
| Page faults | 62 |
| Swaps | 0 |

Raw profile: [macos_profile_main_0.10.0.9000.txt](macos_profile_main_0.10.0.9000.txt)

Instruments trace: [instruments_allocations_main_0.10.0.9000.trace](instruments_allocations_main_0.10.0.9000.trace)
Trace table of contents: [instruments_allocations_main_0.10.0.9000_toc.xml](instruments_allocations_main_0.10.0.9000_toc.xml)
Allocation statistics: [instruments_allocations_main_0.10.0.9000_statistics.xml](instruments_allocations_main_0.10.0.9000_statistics.xml)
Allocation origins: [instruments_allocations_main_0.10.0.9000_allocations.xml](instruments_allocations_main_0.10.0.9000_allocations.xml)
Instruments log: [instruments_allocations_main_0.10.0.9000.log](instruments_allocations_main_0.10.0.9000.log)

Open the `.trace` bundle in Instruments to inspect allocation lifetimes, persistent versus transient allocations, types, and recorded stack traces.

### `dev-native-quadra` (FIMS 0.10.0.9000)

| Metric | Value |
|---|---:|
| Maximum resident set size | 489.28 MiB |
| Peak memory footprint | 382.49 MiB |
| Elapsed time | 6.44 s |
| User CPU time | 6.35 s |
| System CPU time | 0.07 s |
| Page reclaims | 35,203 |
| Page faults | 24 |
| Swaps | 0 |

Raw profile: [macos_profile_dev-native-quadra_0.10.0.9000.txt](macos_profile_dev-native-quadra_0.10.0.9000.txt)

Instruments trace: [instruments_allocations_dev-native-quadra_0.10.0.9000.trace](instruments_allocations_dev-native-quadra_0.10.0.9000.trace)
Trace table of contents: [instruments_allocations_dev-native-quadra_0.10.0.9000_toc.xml](instruments_allocations_dev-native-quadra_0.10.0.9000_toc.xml)
Allocation statistics: [instruments_allocations_dev-native-quadra_0.10.0.9000_statistics.xml](instruments_allocations_dev-native-quadra_0.10.0.9000_statistics.xml)
Allocation origins: [instruments_allocations_dev-native-quadra_0.10.0.9000_allocations.xml](instruments_allocations_dev-native-quadra_0.10.0.9000_allocations.xml)
Instruments log: [instruments_allocations_dev-native-quadra_0.10.0.9000.log](instruments_allocations_dev-native-quadra_0.10.0.9000.log)

Open the `.trace` bundle in Instruments to inspect allocation lifetimes, persistent versus transient allocations, types, and recorded stack traces.

## Interpretation notes

- Compare runs only when both refs use the same model, inputs, and benchmark stage.
- Maximum RSS includes resident code and mapped pages, so it is broader than Massif heap usage.
- Peak footprint is Apple's accounting of the process's physical-memory impact and may be lower than RSS.
- Instruments and the RSS profiler execute the model separately to avoid profiling the Instruments launcher itself.
- The `.trace` bundle is the authoritative detailed allocation record; exported XML is provided for automation.
- macOS and Massif results should be compared within their own profiler type, not directly across operating systems.