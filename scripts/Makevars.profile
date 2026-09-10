# Compiler flags for CPU profiling and timing. Pointed at by R_MAKEVARS_USER,
# which R reads in place of ~/.R/Makevars.
#
# Assignments rather than "+=" on PKG_CXXFLAGS, for the reason given in
# Makevars.debug: PKG_CXXFLAGS is followed by R's own CXXFLAGS on the compile
# line, so it cannot control the optimization level.
#
# Optimized, because an -O0 build can rank hot spots differently from the code
# anyone actually runs, but still fully symbolized so perf and the R-side
# profilers can name a function.
CXXFLAGS = -g -O2 -fno-omit-frame-pointer -fvisibility=default
CFLAGS   = -g -O2 -fno-omit-frame-pointer -fvisibility=default
CXX_VISIBILITY =
C_VISIBILITY   =
