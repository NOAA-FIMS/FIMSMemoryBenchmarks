# Compiler flags for CPU profiling. Pointed at by R_MAKEVARS_USER, which R
# reads in place of ~/.R/Makevars.
#
# 1. Assignments, not "+=" on PKG_CXXFLAGS. R builds the compile line as
#      ALL_CXXFLAGS = $(PKG_CXXFLAGS) ... $(CXXFLAGS)
#    so anything added to PKG_CXXFLAGS is followed by R's own -O2 and loses.
#
# 2. Every CXXnnFLAGS variant. A package that declares a C++ standard is built
#    with that standard's variables: FIMS says C++17, so R uses CXX17FLAGS and
#    ignores CXXFLAGS entirely. Setting only CXXFLAGS silently does nothing.
#
# optimized, so profiles rank the code anyone runs.
CFLAGS      = -O2 -g -fno-omit-frame-pointer -fvisibility=default
CXXFLAGS    = -O2 -g -fno-omit-frame-pointer -fvisibility=default
CXX11FLAGS  = -O2 -g -fno-omit-frame-pointer -fvisibility=default
CXX14FLAGS  = -O2 -g -fno-omit-frame-pointer -fvisibility=default
CXX17FLAGS  = -O2 -g -fno-omit-frame-pointer -fvisibility=default
CXX20FLAGS  = -O2 -g -fno-omit-frame-pointer -fvisibility=default
CXX_VISIBILITY =
C_VISIBILITY   =
