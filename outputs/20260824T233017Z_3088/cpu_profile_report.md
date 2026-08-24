# FIMS CPU Profile Report

Generated: `2026-08-24T23:35:43+00:00`  
Profiler: Instruments Time Profiler

## Summary

Each branch is sampled in a separate model run after its FIMS build is installed.

| Git ref | FIMS version | Capture status | Profile data |
|---|---:|---|---|
| main | 0.10.0.9000 | captured | [instruments_cpu_main_0.10.0.9000.xml](instruments_cpu_main_0.10.0.9000.xml) |
| dev-native-quadra | 0.10.0.9000 | captured | [instruments_cpu_dev-native-quadra_0.10.0.9000.xml](instruments_cpu_dev-native-quadra_0.10.0.9000.xml) |

## Hot symbols by branch

### `main`

| Rank | Symbol | Samples |
|---:|---|---:|
| 1 | `TMBad::global::Complete<TMBad::global::ad_plain::MulOp_<true, true>>::reverse_decr(TMBad::ReverseArgs<double>&)` | 7.26% |
| 2 | `bcEval_loop` | 5.67% |
| 3 | `TMBad::global::Complete<TMBad::global::ad_plain::AddOp_<true, true>>::reverse_decr(TMBad::ReverseArgs<double>&)` | 3.90% |
| 4 | `TMBad::global::hash_sweep(TMBad::global::hash_config) const` | 3.65% |
| 5 | `TMBad::ADFun<TMBad::global::ad_aug>::Jacobian(std::__1::vector<double, std::__1::allocator<double>> const&, std::__1::vector<double, std::__1::allocator<double>> const&)` | 3.08% |
| 6 | `TMBad::global::subgraph_cache_ptr() const` | 2.74% |
| 7 | `std::__1::pair<unsigned long long*, bool> std::__1::__partition_with_equals_on_right[abi:ne190102]<std::__1::_ClassicAlgPolicy, unsigned long long*, std::__1::ranges::less>(unsigned long long*, unsigned long long*, std::__1::ranges::less)` | 2.47% |
| 8 | `_platform_memmove` | 2.36% |
| 9 | `TMBad::ADFun<TMBad::global::ad_aug>::operator()(std::__1::vector<double, std::__1::allocator<double>> const&)` | 2.31% |
| 10 | `Rf_findVarInFrame3` | 2.23% |
| 11 | `Rf_matchArgs_NR` | 1.95% |
| 12 | `radix::radix<unsigned int, unsigned long long>::first_occurance()` | 1.79% |
| 13 | `RunGenCollect` | 1.62% |
| 14 | `findVarLocInFrame` | 1.51% |
| 15 | `CONS_NR` | 1.49% |
| 16 | `SETCAR` | 1.34% |
| 17 | `TMBad::global::extract_sub_inplace(std::__1::vector<bool, std::__1::allocator<bool>>)` | 1.31% |
| 18 | `__bzero` | 1.30% |
| 19 | `TMBad::global::ad_aug::operator+(TMBad::global::ad_aug const&) const` | 1.26% |
| 20 | `TMBad::remap_identical_sub_expressions(TMBad::global&, std::__1::vector<unsigned long long, std::__1::allocator<unsigned long long>>)` | 1.17% |
| 21 | `TMBad::global::extract_sub(std::__1::vector<unsigned long long, std::__1::allocator<unsigned long long>>&, TMBad::global)` | 1.15% |
| 22 | `TMBad::global::Complete<TMBad::global::ad_plain::DivOp_<true, true>>::reverse_decr(TMBad::ReverseArgs<double>&)` | 1.13% |
| 23 | `CAR` | 1.07% |
| 24 | `setup_vcache` | 1.06% |
| 25 | `TMBad::global::operation_stack::push_back(TMBad::global::OperatorPure*)` | 1.05% |
|  | **Top 25 total** | **55.87%** |

### `dev-native-quadra`

| Rank | Symbol | Samples |
|---:|---|---:|
| 1 | `quadra::CompactFirstOrderTape::Evaluate(Eigen::Matrix<double, -1, 1, 0, -1, 1> const&, Eigen::Matrix<double, -1, 1, 0, -1, 1>&)` | 57.93% |
| 2 | `bcEval_loop` | 4.79% |
| 3 | `Rf_findVarInFrame3` | 1.81% |
| 4 | `Rf_matchArgs_NR` | 1.73% |
| 5 | `exp` | 1.44% |
| 6 | `SETCAR` | 1.42% |
| 7 | `RunGenCollect` | 1.35% |
| 8 | `CONS_NR` | 1.27% |
| 9 | `findVarLocInFrame` | 1.14% |
| 10 | `CAR` | 0.78% |
| 11 | `_platform_strcmp$VARIANT$Base` | 0.75% |
| 12 | `setup_vcache` | 0.73% |
| 13 | `Rf_allocVector3` | 0.72% |
| 14 | `Rf_cons` | 0.71% |
| 15 | `Rf_eval` | 0.62% |
| 16 | `__bzero` | 0.61% |
| 17 | `SET_TAG` | 0.61% |
| 18 | `Rf_protect` | 0.57% |
| 19 | `Rf_mkPROMISE` | 0.53% |
| 20 | `SET_PRVALUE` | 0.53% |
| 21 | `Rf_findFun3` | 0.50% |
| 22 | `Rf_NewEnvironment` | 0.42% |
| 23 | `SET_PRENV` | 0.42% |
| 24 | `log` | 0.42% |
| 25 | `R_HashGet` | 0.39% |
|  | **Top 25 total** | **82.19%** |

## Interpretation notes

- Sampling identifies where CPU time is spent without tracing every function call.
- Compare hot-symbol rankings across refs; small percentage changes can be sampling noise.
- Open `.trace` files in Instruments or `perf.data` with perf for full call trees.
