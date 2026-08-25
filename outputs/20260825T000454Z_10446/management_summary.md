# Management Summary: FIMS Native Quadra Evaluation

Prepared: `2026-08-25 00:09:47 UTC`

## Bottom line

- **Numerical results agree.** The two backends start from the same model and parameters and converge to effectively the same joint objective and estimates.
- **Native Quadra materially reduces memory use in the recorded run.** This is the strongest operational benefit observed so far.
- **The benchmark records a reproducible optimized build profile.** This makes the resulting performance comparison suitable for management review.

## Decision scorecard

| Question | Result |
|---|---|
| Do the objective values agree? | Yes — final difference `4.155e-08` |
| Do the initial gradients agree? | Yes — maximum difference `1.746e-10` |
| Do the estimated parameters agree? | Yes — maximum difference `2.292e-05` |
| Did both optimizations converge? | Yes |
| Model scale | 139 fixed effects and 119 recruitment random effects |
| Build profile | `optimized-O2-with-symbols` |

## Performance and memory

| Git ref | FIMS version | Maximum RSS | Peak footprint | Elapsed | Instruments |
|---|---:|---:|---:|---:|---|
| main | 0.10.0.9000 | **4.96 GiB** | 2.99 GiB | 14.99 s | captured |
| dev-native-quadra | 0.10.0.9000 | **489.28 MiB** | 382.49 MiB | 6.44 s | captured |

## What this means

Native Quadra produces the same scientific answer for this benchmark while showing substantially lower memory demand. Lower memory use can support larger models, reduce workstation and cloud requirements, and lower the risk of runs failing because of resource limits.

## Recommended next step

Repeat the optimized benchmark on one additional representative assessment model, then use the combined evidence to decide whether native Quadra should advance toward broader testing.

## Supporting detail

- [Full benchmark report](final_report.md)
- [Joint validation report](joint_validation_report.md)
- [Memory profile report](macos_memory_report.md)
