#' Summarise bootstrap replicates into selection frequencies
#'
#' The R port of `%SUMBOOT` (`bootstrap.summary.sas` in the CORR macro
#' library). For each candidate term: how often it was selected across
#' replicates, and the distribution of its coefficient when it was.
#'
#' `n` counts replicates in which the term was selected, because [boot_select()]
#' leaves an unselected term `NA`. `pct` is `100 * n / n_rep` - the denominator
#' is the replicate count, so `pct` reads as a selection frequency.
#'
#' This function is held to **exact parity** with `%SUMBOOT`: given the same
#' replicate table it must produce the same `n`, `pct`, `mean`, `sd`, `min` and
#' `max`. Resampling and model fitting are not parity-tested; see the package's
#' design spec.
#'
#' @param x A `boot_selection` from [boot_select()], or a numeric matrix with
#'   one row per replicate and one column per term.
#' @return A data frame with columns `variable`, `n`, `pct`, `mean`, `sd`,
#'   `min`, `max`, sorted by descending `n`.
#' @seealso [boot_select()], which produces the replicates; [boot_clusters()]
#'   for the at-least-one count across a group of correlated terms.
#' @examples
#' set.seed(1)
#' n  <- 300
#' x1 <- rnorm(n)
#' df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1,
#'                  x2 = rnorm(n), noise = rnorm(n))
#'
#' fit <- boot_select(df, y ~ x1 + x2 + noise, fit_linear,
#'                    n_rep = 50, seed = 42)
#' boot_summary(fit)
#'
#' # It also takes a bare replicate matrix, which is how the parity fixtures
#' # are checked against %SUMBOOT without needing any cohort data.
#' m <- matrix(c(1, 2, 3, 4, 2, NA, 4, NA), nrow = 4,
#'             dimnames = list(NULL, c("x1", "x2")))
#' boot_summary(m)
#' @export
boot_summary <- function(x) {
  m <- if (inherits(x, "boot_selection")) x$coefficients else x
  if (!is.matrix(m) || !is.numeric(m))
    stop("`x` must be a boot_selection object or a numeric matrix.",
         call. = FALSE)
  # Every statistic below is per-column and reported against a term name. An
  # unnamed matrix otherwise died inside data.frame() with "arguments imply
  # differing number of rows", which says nothing about the real problem.
  if (is.null(colnames(m)))
    stop("`x` must have column names, one per candidate term.", call. = FALSE)

  n_rep <- nrow(m)
  stat <- function(f, col) {
    v <- col[!is.na(col)]
    if (length(v) == 0L) return(NA_real_)
    f(v)
  }
  out <- data.frame(
    variable = colnames(m),
    n    = as.integer(colSums(!is.na(m))),
    pct  = 100 * colSums(!is.na(m)) / n_rep,
    mean = vapply(seq_len(ncol(m)), function(j) stat(mean, m[, j]), numeric(1)),
    sd   = vapply(seq_len(ncol(m)), function(j) stat(stats::sd, m[, j]),
                  numeric(1)),
    min  = vapply(seq_len(ncol(m)), function(j) stat(min, m[, j]), numeric(1)),
    max  = vapply(seq_len(ncol(m)), function(j) stat(max, m[, j]), numeric(1)),
    stringsAsFactors = FALSE
  )
  out <- out[order(-out$n, out$variable), , drop = FALSE]
  rownames(out) <- NULL
  out
}
