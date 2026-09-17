#!/usr/bin/env python3
"""The parsers the benchmark actually depends on.

run_fims_benchmark() asks the summarizers for tidy rows and never for Markdown,
so what has to be right is the parsing: Massif's snapshot format, perf's report
columns, and the allocation origins that say what the peak was spent on.
"""
import tempfile
import unittest
from pathlib import Path

from summarize_massif import parse_massif
from summarize_cpu import perf_symbols, perf_libraries

MASSIF = """\
desc: --massif-out-file=/tmp/out
cmd: /usr/lib/R/bin/exec/R
time_unit: i
#-----------
snapshot=0
#-----------
time=0
mem_heap_B=1024
mem_heap_extra_B=8
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=1
#-----------
time=500
mem_heap_B=8192
mem_heap_extra_B=64
mem_stacks_B=16
heap_tree=peak
n2: 8192 (heap allocation functions)
 n1: 6000 0x1: operator new(unsigned long)
  n0: 6000 0x2: fims::Information<double>::CreateModel()
 n0: 2192 0x3: Rf_allocVector3
#-----------
snapshot=2
#-----------
time=900
mem_heap_B=2048
mem_heap_extra_B=16
mem_stacks_B=0
heap_tree=empty
"""

# Memory stays flat after the peak: snapshot 2 ties the peak total but, like
# most snapshots, carries no allocation tree.
MASSIF_PLATEAU = MASSIF.replace("""snapshot=2
#-----------
time=900
mem_heap_B=2048
mem_heap_extra_B=16
mem_stacks_B=0""", """snapshot=2
#-----------
time=900
mem_heap_B=8192
mem_heap_extra_B=64
mem_stacks_B=16""")

# An allocation FIMS made, reached through R's evaluator: R frames sit further
# out on the stack, and must not claim it.
MASSIF_NESTED = MASSIF.replace("""n2: 8192 (heap allocation functions)
 n1: 6000 0x1: operator new(unsigned long)
  n0: 6000 0x2: fims::Information<double>::CreateModel()""", """n2: 8192 (heap allocation functions)
 n1: 6000 0x1: operator new(unsigned long)
  n1: 6000 0x2: fims::Information<double>::CreateModel()
   n0: 6000 0x4: Rf_eval (in /usr/lib/R/lib/libR.so)""")

# An R vector allocated by R's allocator on Rcpp's behalf: R is the nearest
# frame, but Rcpp is the code responsible.
MASSIF_VIA_RCPP = MASSIF.replace(""" n0: 2192 0x3: Rf_allocVector3""", """ n1: 2192 0x3: Rf_allocVector3 (in /usr/lib/R/lib/libR.so)
  n0: 2192 0x5: Rcpp::wrap<double>(double const&)""")

PERF = """\
# Samples: 4K of event 'cpu-clock'
#
# Overhead  Shared Object     Symbol
# ........  ................  ......
#
    41.20%  FIMS.so           [.] fims::Information<double>::CreateModel  -  -
    12.05%  libR.so           [.] Rf_eval                                 -  -
     0.90%  [unknown]         [.] 0x00007f0000000000                      -  -
"""


class ParserTests(unittest.TestCase):
    def test_massif_peak_is_the_peak_snapshot_not_the_last(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "massif.out.1"
            path.write_text(MASSIF)
            profile = parse_massif(path)
            self.assertEqual(profile.snapshots, 3)
            # The peak snapshot, not snapshot 2, which is where the process ended.
            self.assertEqual(profile.peak_heap, 8192)
            self.assertEqual(profile.peak_total, 8192 + 64 + 16)
            # Retained is the last snapshot: what the process exited holding.
            self.assertEqual(profile.retained_total, 2048 + 16)

    def test_massif_attributes_the_peak_to_its_callers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "massif.out.1"
            path.write_text(MASSIF)
            origins = parse_massif(path).peak_origins
            self.assertEqual(origins.get("FIMS C++ (backend not explicit)"), 6000)
            self.assertEqual(origins.get("R runtime"), 2192)

    def test_massif_origins_survive_a_plateau_after_the_peak(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "massif.out.1"
            path.write_text(MASSIF_PLATEAU)
            profile = parse_massif(path)
            self.assertEqual(profile.peak_total, 8192 + 64 + 16)
            self.assertEqual(profile.peak_origins.get("FIMS C++ (backend not explicit)"), 6000)

    def test_massif_attributes_to_the_nearest_caller_not_to_r_further_out(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "massif.out.1"
            path.write_text(MASSIF_NESTED)
            origins = parse_massif(path).peak_origins
            self.assertEqual(origins.get("FIMS C++ (backend not explicit)"), 6000)
            self.assertEqual(origins.get("R runtime"), 2192)

    def test_massif_names_the_package_even_when_r_allocated_it(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "massif.out.1"
            path.write_text(MASSIF_VIA_RCPP)
            origins = parse_massif(path).peak_origins
            self.assertEqual(origins.get("Rcpp"), 2192)
            self.assertIsNone(origins.get("R runtime"))

    def test_perf_report_columns(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cpu.txt"
            path.write_text(PERF)
            symbols = perf_symbols(path)
            self.assertEqual(symbols[0][1], 41.20)
            self.assertIn("CreateModel", symbols[0][0])
            # The trailing "-  -" srcline columns must not end up in the symbol.
            self.assertFalse(symbols[0][0].endswith("-"))


class LibraryTests(unittest.TestCase):
    def test_perf_share_per_shared_object(self):
        """The shared object column, which perf_symbols() throws away."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cpu.txt"
            path.write_text(PERF)
            libraries = dict(perf_libraries(path))
            self.assertAlmostEqual(libraries["FIMS.so"], 41.20)
            self.assertAlmostEqual(libraries["libR.so"], 12.05)
            # An unresolved object still counts; it is not dropped.
            self.assertAlmostEqual(libraries["[unknown]"], 0.90)


if __name__ == "__main__":
    unittest.main()
