# Ref handling in run_fims_benchmark(), through the function it delegates to.
#
# The upstream version of this test drove compare_fims_refs() in R/main.R and
# checked the refs handed to run_massif.sh. This branch has neither: main.R is
# the analysis script and the driver is run_fims_benchmark(), so the same rules
# are checked directly on resolve_refs().

source(file.path("R", "run_benchmark.R"))

# Any number of refs, first one first, duplicates dropped in order.
stopifnot(identical(
  suppressWarnings(resolve_refs("main", c("dev-xptr-quadra", "dev-native-quadra", "main"))),
  c("main", "dev-xptr-quadra", "dev-native-quadra")
))

# Two refs is the ordinary case.
stopifnot(identical(
  resolve_refs("main", "dev-xptr-quadra"),
  c("main", "dev-xptr-quadra")
))

# One ref is allowed, with a warning: there is nothing to compare it against.
warned <- FALSE
single <- withCallingHandlers(
  resolve_refs("main"),
  warning = function(w) {
    warned <<- TRUE
    invokeRestart("muffleWarning")
  }
)
stopifnot(identical(single, "main"), warned)

# Refs that collide once made filename-safe would overwrite each other's files.
stopifnot(inherits(tryCatch(resolve_refs("a/b", "a_b"), error = identity), "error"))

# Rejected input.
for (refs in list(character(), NA_character_, "", 12, "bad ref")) {
  stopifnot(inherits(
    tryCatch(suppressWarnings(resolve_refs(refs)), error = identity), "error"
  ))
}

cat("Vector interface, duplicate removal, collisions, and input checks passed\n")
