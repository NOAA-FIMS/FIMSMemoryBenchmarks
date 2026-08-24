# FIMS macOS Native Memory Benchmark Report

Generated: `2026-08-24T23:35:43+00:00`  
Host: `macOS 15.7.7 (arm64)`  
Profilers: Instruments Allocations and `/usr/bin/time -l`

## Summary

macOS reports process-level physical memory rather than Massif's allocated heap. Maximum resident set size (RSS) is the primary comparison metric; peak memory footprint is also shown when the host provides it.

| Git ref | FIMS version | Maximum RSS | Peak footprint | Elapsed | Instruments |
|---|---:|---:|---:|---:|---|
| main | 0.10.0.9000 | **5.31 GiB** | 2.95 GiB | 14.77 s | captured |
| dev-native-quadra | 0.10.0.9000 | **431.88 MiB** | 359.71 MiB | 6.40 s | captured |

## Detailed branch comparison

`dev-native-quadra` used **4.89 GiB less maximum RSS** than `main` (-92.06%).

Positive deltas mean the comparison ref used more of that metric; negative deltas mean less.

| Metric | `main` | `dev-native-quadra` | Delta | Change |
|---|---:|---:|---:|---:|
| Maximum RSS | 5.31 GiB | 431.88 MiB | −4.89 GiB | -92.06% |
| Peak footprint | 2.95 GiB | 359.71 MiB | −2.60 GiB | -88.08% |
| Elapsed time | 14.77 s | 6.40 s | -8.37 s | -56.67% |
| User CPU time | 13.60 s | 6.31 s | -7.29 s | -53.60% |
| System CPU time | 1.05 s | 0.06 s | -0.99 s | -94.29% |
| Page reclaims | 525,663 | 31,538 | -494,125 | -94.00% |
| Page faults | 46 | 24 | -22 | -47.83% |
| Swaps | 0 | 0 | +0 | 0.00% |

### Interpretation

- Maximum RSS decreased by 4.89 GiB (-92.06%), from 5.31 GiB to 431.88 MiB.
- Peak memory footprint decreased by 2.60 GiB (-88.08%), from 2.95 GiB to 359.71 MiB.
- Elapsed time decreased by 8.37 s (-56.67%), from 14.77 s to 6.40 s.
- Page faults decreased by 22 (-47.83%), from 46 to 24.

### Instruments allocation totals

Persistent bytes were still allocated at the end of the recording; transient bytes were allocated and freed during the recorded interval.

| Metric | `main` | `dev-native-quadra` | Delta | Change |
|---|---:|---:|---:|---:|
| Persistent bytes | 2.41 GiB | 219.58 MiB | −2.19 GiB | -91.10% |
| Transient bytes | 18.43 GiB | 632.20 MiB | −17.82 GiB | -96.65% |
| Total recorded bytes | 20.84 GiB | 851.78 MiB | −20.01 GiB | -96.01% |
| Persistent allocations | 62,656 | 46,308 | -16,348 | -26.09% |
| Transient allocations | 1,185,449 | 461,530 | -723,919 | -61.07% |
| Total allocations | 1,248,105 | 507,838 | -740,267 | -59.31% |
| Allocation events | 2,431,266 | 969,286 | -1,461,980 | -60.13% |

- Persistent allocated memory decreased by 2.19 GiB (-91.10%), from 2.41 GiB to 219.58 MiB.
- Transient allocated memory decreased by 17.82 GiB (-96.65%), from 18.43 GiB to 632.20 MiB.
- Allocation events decreased by 1,461,980 (-60.13%), from 2,431,266 to 969,286.

### Largest persistent-allocation category changes

| Category | `main` | `dev-native-quadra` | Delta | Change |
|---|---:|---:|---:|---:|
| VM: MALLOC_LARGE | 5.32 GiB | 165.02 MiB | −5.16 GiB | -96.97% |
| Malloc 512.00 MiB | 1.00 GiB | 0 B | −1.00 GiB | -100.00% |
| Malloc 340.67 MiB | 681.34 MiB | 0 B | −681.34 MiB | -100.00% |
| Malloc 256.00 MiB | 256.00 MiB | 0 B | −256.00 MiB | -100.00% |
| Malloc 182.28 MiB | 182.28 MiB | 0 B | −182.28 MiB | -100.00% |
| Malloc 8.00 KiB | 231.38 MiB | 179.30 MiB | −52.09 MiB | -22.51% |
| Malloc 2.69 MiB | 8.06 MiB | 0 B | −8.06 MiB | -100.00% |
| Malloc 8.00 MiB | 8.00 MiB | 0 B | −8.00 MiB | -100.00% |
| Malloc 4.00 MiB | 8.00 MiB | 0 B | −8.00 MiB | -100.00% |
| VM: MALLOC_SMALL | 232.00 MiB | 224.00 MiB | −8.00 MiB | -3.45% |

## Run details

### `main` (FIMS 0.10.0.9000)

| Metric | Value |
|---|---:|
| Maximum resident set size | 5.31 GiB |
| Peak memory footprint | 2.95 GiB |
| Elapsed time | 14.77 s |
| User CPU time | 13.60 s |
| System CPU time | 1.05 s |
| Page reclaims | 525,663 |
| Page faults | 46 |
| Swaps | 0 |

Raw profile: [macos_profile_main_0.10.0.9000.txt](macos_profile_main_0.10.0.9000.txt)

Instruments trace: [instruments_allocations_main_0.10.0.9000.trace](instruments_allocations_main_0.10.0.9000.trace)  
Trace table of contents: [instruments_allocations_main_0.10.0.9000_toc.xml](instruments_allocations_main_0.10.0.9000_toc.xml)  
Allocation statistics: [instruments_allocations_main_0.10.0.9000_statistics.xml](instruments_allocations_main_0.10.0.9000_statistics.xml)
Instruments log: [instruments_allocations_main_0.10.0.9000.log](instruments_allocations_main_0.10.0.9000.log)

Open the `.trace` bundle in Instruments to inspect allocation lifetimes, persistent versus transient allocations, types, and recorded stack traces.

### `dev-native-quadra` (FIMS 0.10.0.9000)

| Metric | Value |
|---|---:|
| Maximum resident set size | 431.88 MiB |
| Peak memory footprint | 359.71 MiB |
| Elapsed time | 6.40 s |
| User CPU time | 6.31 s |
| System CPU time | 0.06 s |
| Page reclaims | 31,538 |
| Page faults | 24 |
| Swaps | 0 |

Raw profile: [macos_profile_dev-native-quadra_0.10.0.9000.txt](macos_profile_dev-native-quadra_0.10.0.9000.txt)

Instruments trace: [instruments_allocations_dev-native-quadra_0.10.0.9000.trace](instruments_allocations_dev-native-quadra_0.10.0.9000.trace)  
Trace table of contents: [instruments_allocations_dev-native-quadra_0.10.0.9000_toc.xml](instruments_allocations_dev-native-quadra_0.10.0.9000_toc.xml)  
Allocation statistics: [instruments_allocations_dev-native-quadra_0.10.0.9000_statistics.xml](instruments_allocations_dev-native-quadra_0.10.0.9000_statistics.xml)
Instruments log: [instruments_allocations_dev-native-quadra_0.10.0.9000.log](instruments_allocations_dev-native-quadra_0.10.0.9000.log)

Open the `.trace` bundle in Instruments to inspect allocation lifetimes, persistent versus transient allocations, types, and recorded stack traces.

## Interpretation notes

- Compare runs only when both refs use the same model, inputs, and benchmark stage.
- Maximum RSS includes resident code and mapped pages, so it is broader than Massif heap usage.
- Peak footprint is Apple's accounting of the process's physical-memory impact and may be lower than RSS.
- Instruments and the RSS profiler execute the model separately to avoid profiling the Instruments launcher itself.
- The `.trace` bundle is the authoritative detailed allocation record; exported XML is provided for automation.
- macOS and Massif results should be compared within their own profiler type, not directly across operating systems.
