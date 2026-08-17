new_boot_selection <- function(coefficients, n_rep, n_attempts, call) {
  structure(
    list(coefficients = coefficients, n_rep = n_rep,
         n_attempts = n_attempts, call = call),
    class = "boot_selection"
  )
}

#' @export
print.boot_selection <- function(x, ...) {
  cat("<boot_selection>\n")
  cat("  replicates: ", x$n_rep, " valid of ", x$n_attempts, " attempts\n",
      sep = "")
  cat("  terms:      ", ncol(x$coefficients), "\n", sep = "")
  cat("Use boot_summary() for per-variable selection frequencies.\n")
  invisible(x)
}

#' @export
summary.boot_selection <- function(object, ...) boot_summary(object)
