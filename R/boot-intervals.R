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

# Draw whole units with replacement, and renumber them.
#
# WHY RENUMBER. %BNMNR sets _PTID=_COUNTER as it draws, BEFORE joining the
# repeated records, and then fits random u ~ normal(0, ...) subject=_PTID. A
# patient drawn twice therefore enters the model as two patients. Reusing the
# original id instead would give the two copies one shared random effect,
# which understates between-unit variance -- the quantity the bootstrap is
# there to estimate. The renumbering is the method, not bookkeeping.
#
# The new id goes in `.boot_unit` so a statistic can group on it. A data
# frame that already has that column is refused rather than overwritten: the
# caller's statistic would otherwise read a column that no longer means what
# they wrote.
#
# `idx_by_unit` is the row indices for each unit, precomputed once by the
# caller with split(). Drawing sample.int() POSITIONS rather than
# sample()-ing the id values themselves means a single unit can never be
# misread as a range -- sample(7, ..., replace = TRUE) on one numeric id >= 1
# draws from 1:7, not "7" repeated, which is exactly the crash this avoids.
# Subsetting `data` once with the concatenated indices, instead of once per
# drawn unit, is what keeps this linear in the resample size rather than
# quadratic.
.draw_units <- function(data, idx_by_unit, n_units) {
  drawn <- idx_by_unit[sample.int(length(idx_by_unit), size = n_units,
                                  replace = TRUE)]
  out <- data[unlist(drawn, use.names = FALSE), , drop = FALSE]
  # rep() over the drawn units' sizes gives each DRAW its own id, so a unit
  # drawn twice becomes two units.
  out[[".boot_unit"]] <- rep(seq_along(drawn), lengths(drawn))
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
#' SAS's `PCTLDEF=1`. A coverage-shaped name passed through `...` (`conf`,
#' `level`, `alpha`, `probs`, `conf.level`) is refused with an error rather
#' than silently forwarded to `statistic` and ignored.
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
    if (!is.character(id) || length(id) != 1L || !id %in% names(data)) {
      stop("`id` must name a single column of `data`; `",
           paste(format(id), collapse = ", "), "` is not a column.",
           call. = FALSE)
    }
    if (".boot_unit" %in% names(data)) {
      stop("`data` already has a `.boot_unit` column, which is the name ",
           "this function gives the redrawn unit. Rename it: overwriting ",
           "it would change what `statistic` reads.", call. = FALSE)
    }
    if (anyNA(data[[id]])) {
      stop("`id` column `", id, "` contains NA. A unit with no identity ",
           "cannot be resampled, and split() drops those rows silently -- ",
           "they would vanish from every replicate without a word.",
           call. = FALSE)
    }
  }
  # The rationale for having no coverage argument is that a function taking
  # no level cannot be handed 95 where it wanted 0.95. `...` goes to
  # `statistic`, so without this a `conf =` would be swallowed silently by
  # any statistic that declares `...` -- which the example in this very file
  # does. Silently ignoring a caller's requested coverage is the failure the
  # design is supposed to make impossible, so it is refused by name.
  reserved <- intersect(names(list(...)),
                        c("conf", "level", "alpha", "probs", "conf.level"))
  if (length(reserved)) {
    stop("`boot_predict_ci()` has no coverage argument, and `", reserved[[1L]],
         "` would have been passed to `statistic` and ignored. Coverage is ",
         "fixed: every replicate yields both the 95% and the 68% band, in ",
         "the `cll_p95`, `cll_p68`, `clu_p68` and `clu_p95` columns.",
         call. = FALSE)
  }
  if (!is.null(seed)) set.seed(seed)

  n <- nrow(data)
  # match() against the observed values, NOT the column itself: split() keeps
  # empty factor levels, so a factor `id` carrying an unused level -- the
  # ordinary result of subsetting without droplevels() -- would become a
  # phantom unit with no rows that the draw could still select. A replicate
  # would then hold fewer real units than requested, and sometimes none at
  # all, understating exactly the between-unit variance the renumbering
  # below exists to preserve.
  idx_by_unit <- if (is.null(id)) {
    NULL
  } else {
    keys <- match(data[[id]], unique(data[[id]]))
    unname(split(seq_len(n), keys))
  }
  n_units <- if (is.null(id)) n else length(idx_by_unit)
  n_draw <- max(1L, round(n_units * fraction))
  draw_one <- if (is.null(id)) {
    function() {
      data[sample.int(n, size = n_draw, replace = TRUE), , drop = FALSE]
    }
  } else {
    function() .draw_units(data, idx_by_unit, n_draw)
  }
  .t0 <- proc.time()[["elapsed"]]

  # The first valid replicate fixes the names. A later one disagreeing is
  # discarded like any other failure -- %BNMNR's &_ON=&_BN check, made
  # stricter because a matching COUNT with different names would assemble one
  # row of the percentile table out of two different quantities.
  names_seen <- NULL
  one <- function(d) {
    v <- statistic(d, ...)
    if (is.null(v)) return(NULL)
    # is.finite() is already FALSE for NA, NaN, Inf and -Inf, so there is no
    # separate anyNA() check to make here -- do not restore one.
    if (!is.numeric(v) || is.null(names(v)) || !all(is.finite(v))) {
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
    draw = draw_one,
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
    n_rows = as.integer(n), n_units = as.integer(n_units),
    n_names = ncol(m),
    elapsed_mins = (proc.time()[["elapsed"]] - .t0) / 60,
    package = as.character(utils::packageVersion("hvtiRbootstrap"))
  )

  new_boot_intervals(m, .interval_table(m), n_rep = as.integer(n_rep),
                     n_attempts = drawn$n_attempts, call = match.call(),
                     control = control)
}
