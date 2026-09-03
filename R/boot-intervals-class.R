# The interval branch's object. Deliberately shares nothing with
# boot_selection: that class's coefficients matrix carries NA to mean "not
# selected", and reusing it here would invite a reader to run boot_summary()
# over estimates where missingness has no such meaning.
new_boot_intervals <- function(estimates, intervals, n_rep, n_attempts, call,
                               control = NULL) {
  structure(
    list(estimates = estimates, intervals = intervals, n_rep = n_rep,
         n_attempts = n_attempts, call = call, control = control),
    class = "boot_intervals"
  )
}

#' @export
print.boot_intervals <- function(x, ...) {
  cat("<boot_intervals>\n")
  cat("  replicates: ", x$n_rep, " valid of ", x$n_attempts, " attempts\n",
      sep = "")
  cat("  quantities: ", ncol(x$estimates), "\n", sep = "")
  cat("Bands are POINTWISE 95% and 68% percentile intervals.\n")
  cat("Use summary() for the per-quantity table.\n")
  invisible(x)
}

#' @export
summary.boot_intervals <- function(object, ...) object$intervals
