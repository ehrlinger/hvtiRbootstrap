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

# The bag-side summary: boot_summary() keyed the way a bag is keyed, plus the
# spread of each coefficient across the replicates that selected it.
#
# WHY ONE CONSTRUCTOR. boot_bag() and boot_pool_chunks() both fill
# `$boot$summary`, and before this they built it separately -- seven columns
# keyed `variable` from one, nine keyed `parameter` from the other. A renderer
# then saw a different shape depending on whether the run happened to be
# chunked. Nothing inside the package reads that slot, so nothing caught it.
# Sharing the constructor makes the shapes agree by construction.
#
# WHY `parameter` RATHER THAN `variable`. `$boot$replicates`, boot_health(),
# and boot_validate()'s own documented example all say `parameter`. Only
# boot_summary() says `variable`, and boot_summary() is the standalone %SUMBOOT
# port rather than a bag -- it keeps its own key.
#
# WHY THESE ARE NOT CALLED ci_lower/ci_upper. They are computed over the
# replicates in which the term was SELECTED, so for a term chosen half the time
# the interval is over half the replicates. That is not a confidence interval
# for the coefficient, and it is perverse in the direction that matters: the
# weaker the term, the narrower the interval looks. It is a sibling of the
# mean/sd/min/max above, which are conditional in exactly the same way and
# always have been. The name says selection, and deliberately does not resemble
# the interval branch's cll_p95/clu_p95.
#
# WHY type = 4. SAS PROC STDIZE runs PCTLDEF=1, which is the weighted average
# at x_(np) -- R's type 4, not the type 7 default.
.bag_summary <- function(m) {
  out <- boot_summary(m)
  names(out)[names(out) == "variable"] <- "parameter"

  # NA dropped per column rather than na.rm = TRUE, so that a column of
  # nothing yields NA instead of an error, matching boot_summary()'s own
  # handling of an undefined statistic.
  q <- function(col, p) {
    v <- col[!is.na(col)]
    if (length(v) == 0L) return(NA_real_)
    unname(stats::quantile(v, p, type = 4))
  }
  # Computed over the matrix's OWN column order, then permuted into out's row
  # order -- never matched back to it by name. match(out$parameter,
  # colnames(m)) returns the FIRST hit for a name, so two same-named columns
  # would let a row's quantiles come from a different column than
  # boot_summary() took that row's mean/sd/min/max from. Not reachable
  # through either caller today, but nothing here should assume it can't
  # happen.
  q025 <- vapply(seq_len(ncol(m)), function(k) q(m[, k], 0.025), numeric(1))
  q975 <- vapply(seq_len(ncol(m)), function(k) q(m[, k], 0.975), numeric(1))
  # boot_summary()'s own sort order(-out$n, out$variable), recomputed on the
  # same inputs rather than read back off `out`, so it reproduces that exact
  # permutation -- tie order among duplicate names included -- with no
  # dependence on names being unique.
  perm <- order(-colSums(!is.na(m)), colnames(m))
  out$sel_q025 <- q025[perm]
  out$sel_q975 <- q975[perm]

  rownames(out) <- NULL
  out
}
