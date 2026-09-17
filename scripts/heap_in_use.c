/* Bytes the C allocator has handed out and not had back, R and C++ alike.
 * glibc only. Compiled at run time by R/run_lifecycle.R. */
#include <malloc.h>
#include <Rinternals.h>

SEXP heap_in_use(void) {
  struct mallinfo2 m = mallinfo2();
  return Rf_ScalarReal((double) (m.uordblks + m.hblkhd));
}
