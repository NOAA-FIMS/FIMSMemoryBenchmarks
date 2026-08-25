# FIMS Joint Objective Validation

Both branches use the same wrapper-built model, starting values, joint fixed/random objective, and `nlminb` controls.

## Optimization summary

| Git ref | Backend | Fixed | Random | Initial objective | Final objective | Final gradient norm | Convergence | Iterations | Function evals | Gradient evals | Elapsed |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| main | TMB | 139 | 119 | 168417.46 | 14115.796 | 0.043716689 | 0 | 951 | 1464 | 952 | 1.954s |
| dev-native-quadra | native | 139 | 119 | 168417.46 | 14115.796 | 0.029366961 | 0 | 966 | 1497 | 967 | 6.355s |

## Agreement

| Metric | Difference |
|---|---:|
| Initial objective absolute difference | 8.7311491e-11 |
| Initial parameters maximum absolute difference | 0 |
| Initial gradient maximum absolute difference | 1.7462298e-10 |
| Final objective absolute difference | 4.1545718e-08 |
| Final parameters maximum absolute difference | 2.2920784e-05 |
| Final gradient maximum absolute difference | 0.016600493 |
| Iteration count difference | 15 |
| Function evaluation count difference | 33 |
| Gradient evaluation count difference | 15 |

Parameter and gradient differences are calculated after aligning logical parameter names and converting `log_slope` to the natural slope scale.

Canonical parameter sets agree: **yes**. Convergence codes agree: **yes**.
