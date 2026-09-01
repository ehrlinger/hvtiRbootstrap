# `control` defaults to NULL rather than being required. This constructor is
# internal, but an object saved by 0.9.0 and reloaded under 0.9.1 carries no
# control either, and boot_bag() refuses THAT case by name -- which it can only
# do if the field is simply absent rather than the object being malformed.
#
# The distinction is absent-and-fine versus malformed, NOT absent versus
# present-but-NULL. `list(control = NULL)` does keep a named element, so a
# defaulted construction is not the same shape as an 0.9.0 object -- and that
# does not matter, because `is.null()` cannot tell them apart and `is.null()`
# is how this package reads every optional field. Omitting the slot instead
# would make a classed object's names() vary by construction path, to preserve
# a difference nothing reads.
new_boot_selection <- function(coefficients, n_rep, n_attempts, call,
                               control = NULL) {
  structure(
    list(coefficients = coefficients, n_rep = n_rep,
         n_attempts = n_attempts, call = call, control = control),
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
