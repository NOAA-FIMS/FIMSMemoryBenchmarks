# FIMS CPU Profile Report

Generated: `2026-08-25T00:09:47+00:00`
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
| 1 | `TMBad::global::Complete<TMBad::global::ad_plain::MulOp_<true, true>>::reverse_decr(TMBad::ReverseArgs<double>&)` | 6.42% |
| 2 | `bcEval_loop` | 5.86% |
| 3 | `TMBad::global::Complete<TMBad::global::ad_plain::AddOp_<true, true>>::reverse_decr(TMBad::ReverseArgs<double>&)` | 3.64% |
| 4 | `TMBad::global::subgraph_cache_ptr() const` | 2.91% |
| 5 | `TMBad::ADFun<TMBad::global::ad_aug>::Jacobian(std::__1::vector<double, std::__1::allocator<double>> const&, std::__1::vector<double, std::__1::allocator<double>> const&)` | 2.72% |
| 6 | `std::__1::pair<unsigned long long*, bool> std::__1::__partition_with_equals_on_right[abi:ne190102]<std::__1::_ClassicAlgPolicy, unsigned long long*, std::__1::ranges::less>(unsigned long long*, unsigned long long*, std::__1::ranges::less)` | 2.61% |
| 7 | `_platform_memmove` | 2.48% |
| 8 | `Rf_findVarInFrame3` | 2.20% |
| 9 | `TMBad::ADFun<TMBad::global::ad_aug>::operator()(std::__1::vector<double, std::__1::allocator<double>> const&)` | 2.11% |
| 10 | `void radix::radix<unsigned long, unsigned long long>::run_sort<true>()` | 2.10% |
| 11 | `Rf_matchArgs_NR` | 2.08% |
| 12 | `CONS_NR` | 1.72% |
| 13 | `RunGenCollect` | 1.68% |
| 14 | `void radix::radix<unsigned int, unsigned long long>::run_sort<true>()` | 1.53% |
| 15 | `TMBad::global::extract_sub_inplace(std::__1::vector<bool, std::__1::allocator<bool>>)` | 1.46% |
| 16 | `findVarLocInFrame` | 1.43% |
| 17 | `TMBad::global::extract_sub(std::__1::vector<unsigned long long, std::__1::allocator<unsigned long long>>&, TMBad::global)` | 1.42% |
| 18 | `__bzero` | 1.36% |
| 19 | `SETCAR` | 1.35% |
| 20 | `TMBad::global::hash_sweep(TMBad::global::hash_config) const` | 1.31% |
| 21 | `TMBad::global::ad_plain TMBad::global::add_to_stack<TMBad::global::ad_plain::AddOp_<true, true>>(TMBad::global::ad_plain const&, TMBad::global::ad_plain const&)` | 1.18% |
| 22 | `TMBad::global::operation_stack::push_back(TMBad::global::OperatorPure*)` | 1.16% |
| 23 | `TMBad::remap_identical_sub_expressions(TMBad::global&, std::__1::vector<unsigned long long, std::__1::allocator<unsigned long long>>)` | 1.12% |
| 24 | `_platform_strcmp$VARIANT$Base` | 1.00% |
| 25 | `TMBad::global::Complete<TMBad::global::ad_plain::DivOp_<true, true>>::reverse_decr(TMBad::ReverseArgs<double>&)` | 0.98% |
|  | **Top 25 total** | **53.84%** |

### `dev-native-quadra`

| Rank | Symbol | Samples |
|---:|---|---:|
| 1 | `quadra::CompactFirstOrderTape::Evaluate(Eigen::Matrix<double, -1, 1, 0, -1, 1> const&, Eigen::Matrix<double, -1, 1, 0, -1, 1>&)` | 36.22% |
| 2 | `quadra::CompactFirstOrderTape::Forward()` | 21.52% |
| 3 | `bcEval_loop` | 5.09% |
| 4 | `Rf_findVarInFrame3` | 1.76% |
| 5 | `Rf_matchArgs_NR` | 1.71% |
| 6 | `exp` | 1.58% |
| 7 | `findVarLocInFrame` | 1.38% |
| 8 | `RunGenCollect` | 1.31% |
| 9 | `CONS_NR` | 1.21% |
| 10 | `SETCAR` | 1.18% |
| 11 | `Rf_eval` | 0.81% |
| 12 | `CAR` | 0.77% |
| 13 | `Rf_cons` | 0.75% |
| 14 | `_platform_strcmp$VARIANT$Base` | 0.72% |
| 15 | `setup_vcache` | 0.67% |
| 16 | `Rf_protect` | 0.66% |
| 17 | `SET_TAG` | 0.64% |
| 18 | `Rf_allocVector3` | 0.63% |
| 19 | `__bzero` | 0.63% |
| 20 | `Rf_findFun3` | 0.55% |
| 21 | `R_HashGet` | 0.51% |
| 22 | `log` | 0.49% |
| 23 | `Rf_mkPROMISE` | 0.44% |
| 24 | `Rf_length` | 0.42% |
| 25 | `DYLD-STUB$$exp` | 0.41% |
|  | **Top 25 total** | **82.06%** |

## Interpretation notes

- Sampling identifies where CPU time is spent without tracing every function call.
- Compare hot-symbol rankings across refs; small percentage changes can be sampling noise.
- Open `.trace` files in Instruments or `perf.data` with perf for full call trees.
