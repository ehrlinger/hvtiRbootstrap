# The percentile points every bn.* macro asks PROC STDIZE for, and the names it
# gives them. 16 and 84 are the 68% interval -- plus or minus one standard
# error, to two figures -- and 2.5/97.5 the 95%.
#
# COVERAGE LIVES IN THE COLUMN NAME. Not one macro in the family takes a
# coverage level: they hardcode PCTLPTS and return both bands, distinguished by
# name. That is stronger than a `conf` argument, because a renderer selects a
# column rather than reading a field it might forget, and a function that takes
# no level cannot be handed 95 where it wanted 0.95.
#
# `median` is named for what it is. %BNMNR calls it MN_RES, which reads as a
# mean; it is PCTLPTS=50. The misnomer is not inherited.
.ci_points <- c(cll_p95 = 0.025, cll_p68 = 0.16, median = 0.50,
                clu_p68 = 0.84, clu_p95 = 0.975)

# One row per quantity, percentiles taken down the replicates.
#
# THE BAND IS POINTWISE. Each column is summarised independently, which is what
# %BNMNR does -- transpose, one PROC STDIZE, transpose back. It is not a
# simultaneous band for a curve drawn through the columns, and the roxygen on
# boot_predict_ci() says so.
#
# type = 4 is SAS PCTLDEF=1, the weighted average at x_(np). R's default is
# type 7 and disagrees: on 1..100 it puts P2.5 at 3.475 rather than 2.5.
.interval_table <- function(m) {
  if (!is.matrix(m) || !is.numeric(m)) {
    stop("`m` must be a numeric matrix of replicate estimates.", call. = FALSE)
  }
  if (is.null(colnames(m))) {
    stop("`m` must have column names, one per estimated quantity.",
         call. = FALSE)
  }
  if (anyNA(m)) {
    stop("`m` has missing estimates. On this branch a replicate either ",
         "estimates every quantity or is discarded, so a missing value here ",
         "would narrow a band rather than record a choice.", call. = FALSE)
  }

  # unname() because quantile() labels its result "2.5%", "16%", ... and
  # vapply compares names against FUN.VALUE.
  q <- vapply(seq_len(ncol(m)), function(j) {
    unname(stats::quantile(m[, j], .ci_points, type = 4))
  }, numeric(length(.ci_points)))
  out <- data.frame(parameter = colnames(m), stringsAsFactors = FALSE)
  for (i in seq_along(.ci_points)) {
    out[[names(.ci_points)[i]]] <- unname(q[i, ])
  }
  rownames(out) <- NULL
  out
}

#' Band an estimate by bootstrap resampling
#'
#' The R port of `%BNMNR` and `%BNPREV` (`bn.*` in the CORR macro library).
#' Resamples `data`, computes `statistic` on each replicate, and reports the
#' percentile intervals of each estimated quantity.
#'
#' This is the **interval** branch. It is not variable selection: nothing is
#' chosen, the replicates are a distribution rather than a vote, and there is
#' no `NA` semantics. For selection, see [boot_select()].
#'
#' `statistic` is the fitter contract with the selection semantics removed. It
#' takes one resampled frame and returns a **named numeric vector** of that
#' replicate's estimates, or `NULL` when the replicate did not fit. The names
#' are the quantities banded, so a caller wanting a curve evaluates it on
#' their own grid inside `statistic` and names the elements -- which is what
#' the macro does too, in a `PROC NLMIXED` block the analyst edits.
#'
#' **The bands are pointwise.** Each quantity is summarised independently, as
#' `%BNMNR` does. A curve drawn through `cll_p95` is the 2.5th percentile at
#' each point, not a 95% region for the curve.
#'
#' No argument sets a coverage level, here or anywhere in this package. The
#' macros do not take one either: they hardcode
#' `PCTLPTS=2.5 16 50 84 97.5` and return both bands in columns named for
#' their coverage. Percentiles use [stats::quantile()] `type = 4`, which is
#' SAS's `PCTLDEF=1`.
#'
#' @param data A data frame.
#' @param statistic Function of `(data, ...)` returning a named numeric vector
#'   of one replicate's estimates, or `NULL` if the replicate failed.
#'   `%BNMNR` equivalent: the `PROC NLMIXED` block.
#' @param n_rep Number of **valid** replicates (`%BNMNR` `RESAMPL=`).
#'   **Divergence:** the macro defaults to 100; this defaults to 1000,
#'   matching [boot_select()] in this package. A hundred replicates puts the
#'   2.5th percentile on the third order statistic, where it is visibly
#'   unstable. Pass `n_rep = 100` to reproduce the macro.
#' @param fraction Fraction of units drawn per replicate (`%BNMNR`
#'   `FRACTION=`). Applied, as the macro applies it -- unlike `%bootreg`,
#'   which computes it and then draws the full size anyway.
#' @param id Column naming the resampling unit, or `NULL` to draw rows. When
#'   given, units are drawn with replacement and **renumbered**, so a unit
#'   drawn twice becomes two distinct units; the new id is in a `.boot_unit`
#'   column. `%BNMNR` equivalent: the patient-level `INDAT=` joined to the
#'   repeated `INMULT=`.
#' @param max_attempts Budget of draws before giving up. **Divergence:**
#'   `%BNMNR` has no cap and never terminates when every replicate fails.
#'   Pass `Inf` to restore that.
#' @param seed Optional integer for reproducibility (`%BNMNR` `SEED=`).
#' @param ... Passed to `statistic`.
#' @return An object of class `boot_intervals`. `$estimates` is a matrix with
#'   one row per valid replicate and one column per quantity; `$intervals` is
#'   the per-quantity table with columns `parameter`, `cll_p95`, `cll_p68`,
#'   `median`, `clu_p68`, `clu_p95`. `$control` records the run's settings.
#' @seealso [boot_select()] for the selection branch.
#' @examples
#' # The names of the returned vector are the quantities banded. Here, two
#' # summaries of the same column; in a real screen they are typically a
#' # fitted curve evaluated on a grid.
#' df <- data.frame(x = rnorm(200))
#' est <- function(d, ...) c(mean = mean(d$x), sd = sd(d$x))
#'
#' r <- boot_predict_ci(df, est, n_rep = 100, seed = 42)
#' r
#' summary(r)
#' @export
boot_predict_ci <- function(data, statistic, n_rep = 1000, fraction = 1,
                            id = NULL, max_attempts = 10 * n_rep,
                            seed = NULL, ...) {
  # Restore the caller's stream FIRST, before any argument promise is forced,
  # for the reason boot_select() documents at length: `data` is often an
  # expression that itself draws.
  if (!is.null(seed)) withr::local_preserve_seed()
  if (!is.data.frame(data) || nrow(data) == 0L) {
    stop("`data` must be a data frame with at least one row.", call. = FALSE)
  }
  if (!is.function(statistic)) {
    stop("`statistic` must be a function of (data, ...) returning a named ",
         "numeric vector, or NULL.", call. = FALSE)
  }
  if (!is.numeric(fraction) || length(fraction) != 1L || is.na(fraction) ||
        fraction <= 0 || fraction > 1) {
    stop("`fraction` must be greater than 0 and at most 1.", call. = FALSE)
  }
  if (!is.numeric(n_rep) || length(n_rep) != 1L || is.na(n_rep) ||
        n_rep < 1 || n_rep != trunc(n_rep) || is.infinite(n_rep)) {
    stop("`n_rep` must be a positive whole number of replicates.",
         call. = FALSE)
  }
  if (!is.numeric(max_attempts) || length(max_attempts) != 1L ||
        is.na(max_attempts) || max_attempts < n_rep ||
        (is.finite(max_attempts) && max_attempts != trunc(max_attempts))) {
    stop("`max_attempts` must be a whole number at least as large as ",
         "`n_rep`, or `Inf`.", call. = FALSE)
  }
  if (!is.null(id)) {
    stop("`id` is not implemented yet.", call. = FALSE)
  }
  if (!is.null(seed)) set.seed(seed)

  n <- nrow(data)
  n_draw <- max(1L, round(n * fraction))
  .t0 <- proc.time()[["elapsed"]]

  # The first valid replicate fixes the names. A later one disagreeing is
  # discarded like any other failure -- %BNMNR's &_ON=&_BN check, made
  # stricter because a matching COUNT with different names would assemble one
  # row of the percentile table out of two different quantities.
  names_seen <- NULL
  one <- function(d) {
    v <- statistic(d, ...)
    if (is.null(v)) return(NULL)
    if (!is.numeric(v) || is.null(names(v)) || anyNA(v) ||
          !all(is.finite(v))) {
      return(NULL)
    }
    if (is.null(names_seen)) {
      names_seen <<- names(v)
    } else if (!identical(names(v), names_seen)) {
      return(NULL)
    }
    v
  }

  drawn <- .boot_resample(
    draw = function() {
      data[sample.int(n, size = n_draw, replace = TRUE), , drop = FALSE]
    },
    fit = one, n_rep = n_rep, max_attempts = max_attempts,
    caller = "boot_predict_ci", noun = "replicates",
    hint = paste0("`statistic` returned NULL, a non-finite value, or a ",
                  "different set of names on most replicates.")
  )

  m <- do.call(rbind, drawn$results)
  rownames(m) <- NULL

  control <- list(
    fraction = fraction, id = if (is.null(id)) NA_character_ else id,
    seed = if (is.null(seed)) NA_real_ else as.numeric(seed),
    n_rows = as.integer(n), n_units = as.integer(n),
    n_names = ncol(m),
    elapsed_mins = (proc.time()[["elapsed"]] - .t0) / 60,
    package = as.character(utils::packageVersion("hvtiRbootstrap"))
  )

  new_boot_intervals(m, .interval_table(m), n_rep = as.integer(n_rep),
                     n_attempts = drawn$n_attempts, call = match.call(),
                     control = control)
}
