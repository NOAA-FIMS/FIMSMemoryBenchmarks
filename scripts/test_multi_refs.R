source('R/main.R')
captured <- NULL
system2 <- function(command, args, env) {
  captured <<- list(command = command, args = args, env = env)
  0L
}
suppressMessages(compare_fims_refs(c('main', 'dev-xptr-quadra', 'dev-native-quadra', 'main')))
stopifnot(identical(tail(captured$args, 3), shQuote(c('main', 'dev-xptr-quadra', 'dev-native-quadra'))))
suppressMessages(compare_fims_branches('main', 'dev-xptr-quadra'))
stopifnot(identical(tail(captured$args, 2), shQuote(c('main', 'dev-xptr-quadra'))))
for (refs in list(character(), NA_character_, '', 12, 'bad ref')) {
  stopifnot(inherits(tryCatch(compare_fims_refs(refs), error=identity), 'error'))
}
cat('Vector interface, duplicate removal, legacy wrapper, and input checks passed\n')
