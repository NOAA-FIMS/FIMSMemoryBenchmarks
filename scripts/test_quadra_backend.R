source(file.path('R', 'setup_FIMS.R'))
namespace <- new.env(parent = baseenv())
add_api <- function(prefix) {
  for (name in c('evaluate', 'fit', 'sdreport')) {
    assign(paste0(prefix, name), function(...) NULL, envir = namespace)
  }
}
stopifnot(is.null(resolve_quadra_api(namespace)))
add_api('native_quadra_')
stopifnot(resolve_quadra_api(namespace)$backend == 'native')
add_api('quadra_')
stopifnot(resolve_quadra_api(namespace)$backend == 'xptr')
rm(quadra_fit, envir = namespace)
stopifnot(resolve_quadra_api(namespace)$backend == 'native')
rm(native_quadra_fit, envir = namespace)
stopifnot(is.null(resolve_quadra_api(namespace)))
# Functions inherited from an attached package must not select a backend.
child <- new.env(parent = namespace)
add_api('quadra_')
stopifnot(is.null(resolve_quadra_api(child)))
cat('Backend selection checks passed\n')
