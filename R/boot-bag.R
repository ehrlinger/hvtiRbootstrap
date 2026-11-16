#' A screen the reporting layer can read
#'
#' @description
#' Convert a [boot_select()] result into the bag that [boot_validate()] accepts
#' and every reporting function reads.
#'
#' @details
#' [boot_select()] returns a **wide** object: one row per replicate, one column
#' per term, `NA` where a term was not selected. The reporting layer reads a
#' **long** one, because it was extracted from a hazard runner that writes long.
#' Nothing converted between them, so this package's own screen function could
#' not reach its own report and every study would have hand-written the pivot
#' plus nine provenance fields. This is that conversion, written once.
#'
#' **The pivot drops `NA` rather than writing it.** That is not an optimisation:
#' [boot_frequencies()] counts a term's rows against `n_boot`, so a row written
#' for an unselected term would be counted as a selection and every frequency
#' would rise. The replicate count travels in `n_boot`, never in the row count.
#'
#' Everything the run knows about itself comes from `x$control` rather than from
#' an argument, so a bag cannot claim an entry level the screen did not use. The
#' arguments here are the facts [boot_select()] cannot know: which terms are the
#' base model, how many candidates existed before the runner dropped any, what
#' dataset was screened, and what was dropped.
#'
#' @param x A `boot_selection` from [boot_select()], run under 0.9.2 or later.
#'   An object from an earlier version carries no `$control` and is refused by
#'   name rather than failing on an absent list element.
#' @param base_params Character. The terms that are the base model rather than
#'   candidates. They are excluded from every frequency, and the first of them
#'   is the parameter [boot_health()] watches for a zero standard deviation.
#'   Must name terms the screen carries. **A Cox model has no intercept**, so
#'   `"(Intercept)"` copied from a logistic runner names nothing and is refused.
#' @param requested Numeric. How many candidates the runner **offered**, before
#'   it dropped any. Not derivable here: a candidate dropped before screening
#'   never became a column.
#' @param manifest A named list describing the dataset screened, indexed by
#'   name. `list(sha256 = ...)` at minimum.
#' @param dropped Optional data frame of candidates dropped before screening, as
#'   [boot_dropped()] reports it. Absent means nothing was dropped.
#' @param usable Optional numeric, checked rather than used. Supply it to assert
#'   the count the runner believed it screened; a disagreement with the screen's
#'   own term count is refused, because one of the two is describing a different
#'   run.
#'
#' @return A list carrying the fields [boot_validate()] requires: `n_boot`,
#'   `seed`, `slentry`, `slstay`, `base_params`, `requested`, `usable`,
#'   `n_rows`, `elapsed_mins`, `manifest`, `dropped` when supplied, and `boot`
#'   holding `replicates`, `summary`, `n_success` and `n_failed`. It also
#'   carries what [boot_pool_chunks()] checks before pooling two bags: the
#'   engine (`engine`, the package version, and `engine_sha`, its commit or
#'   `NA`), the model (`fitter` and `formula`), `method`, `max_steps`,
#'   `fraction` and `resampled` (always `"rows"`), plus `rng_kind`. A screen
#'   built before this field existed records no model, so its bag carries
#'   none and [boot_pool_chunks()] refuses it. Under `select = "none"`,
#'   `slentry`, `slstay` and `max_steps` are `NA`: no selection ran, so no
#'   level was used.
#'   `boot$summary` is keyed `parameter` -- as `boot$replicates` and
#'   [boot_health()] are, and as [boot_pool_chunks()] returns -- rather than
#'   [boot_summary()]'s `variable`, and carries `sel_q025` and `sel_q975`
#'   alongside the `%SUMBOOT` statistics. Those two are the spread of the
#'   coefficient across the replicates that **selected** it, not a confidence
#'   interval: a term chosen half the time has an interval over half the
#'   replicates.
#'   `provenance` is the hvtiR family's shared provenance record, copied
#'   from the screen.
#'   Validated before it is returned, so this function cannot emit a bag that a
#'   report will refuse three chunks into a render.
#'
#' @seealso [boot_select()] for the screen, [boot_provenance()] and
#'   [boot_frequencies()] for what reads the result.
#'
#' @examples
#' set.seed(1)
#' n  <- 200
#' x1 <- rnorm(n)
#' df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1, x2 = rnorm(n))
#' fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_boot = 10, seed = 42)
#' bag <- boot_bag(fit, base_params = "(Intercept)", requested = 2,
#'                 manifest = list(sha256 = "example"))
#' boot_frequencies(bag)
#'
#' @export
boot_bag <- function(x, base_params, requested, manifest, dropped = NULL,
                     usable = NULL) {
  if (!inherits(x, "boot_selection")) {
    .abort("`x` must be a boot_selection from boot_select(), found ",
           class(x)[1L], ".", class = "bag_refused")
  }
  ctl <- x[["control"]]
  if (!is.list(ctl)) {
    .abort("This boot_selection predates hvtiRbootstrap 0.9.2 and carries no ",
           "`$control`, so the entry and stay levels, the seed and the row ",
           "count it ran under are not recoverable from it.\nRe-run the ",
           "screen under 0.9.2 or later.", class = "bag_refused")
  }
  # length-1 checked before is.na(): a hand-edited control with no `seed` gives
  # is.na(NULL) = logical(0), and `if (logical(0))` errors with "argument is of
  # length zero", replacing the diagnosis below with one that names nothing.
  if (length(ctl$seed) != 1L || is.na(ctl$seed)) {
    .abort("This screen did not record a seed, so the report it feeds could ",
           "not be reproduced and the provenance table would print a blank ",
           "where the seed belongs.\nRe-run boot_select() with `seed =`.",
           class = "bag_refused")
  }

  m <- x$coefficients
  terms_seen <- colnames(m)
  if (!all(base_params %in% terms_seen)) {
    .abort("`base_params` names ",
           paste(setdiff(base_params, terms_seen), collapse = ", "),
           ", which is not among the screen's terms. Every frequency ",
           "excludes the base model, so a name that matches nothing excludes ",
           "nothing and reports the base model as a candidate.\nA Cox screen ",
           "has no intercept: name the terms you forced instead.",
           class = "bag_refused")
  }
  # Whole numbers, checked rather than truncated. as.integer(5.7) is 5, so a
  # fractional count would silently under-report the pool the frequencies are
  # conditional on. boot_select() guards n_rep the same way and for the same
  # reason; this is that convention, not a second one.
  .whole <- function(v, what) {
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0 ||
          v != trunc(v)) {
      .abort("`", what, "` must be a single whole number of candidates, found ",
             paste(format(v), collapse = ", "), ".", class = "bag_refused")
    }
    as.integer(v)
  }
  requested <- .whole(requested, "requested")

  n_usable <- length(setdiff(terms_seen, base_params))
  if (!is.null(usable) && !identical(.whole(usable, "usable"), n_usable)) {
    .abort("The runner reports ", .whole(usable, "usable"), " usable ",
           "candidates; the screen carries ", n_usable, ". One of the two is ",
           "describing a different run.", class = "bag_refused")
  }

  # A pool cannot be smaller than what came out of it. `requested` counts the
  # candidates OFFERED, before the runner dropped any, so it is at least the
  # number the screen carries. A smaller value is not a near-miss: the
  # provenance table would report fewer offered than usable, and a selection
  # frequency is conditional on the pool, so the figure a reader takes away is
  # attributed to a pool that never existed.
  if (requested < n_usable) {
    .abort("`requested` is ", requested, " but the screen carries ", n_usable,
           " candidates. `requested` counts the pool OFFERED, before anything ",
           "was dropped, so it cannot be smaller than what was screened.",
           class = "bag_refused")
  }

  # Long form, NA dropped. See @details: a row written for an unselected term
  # would be counted as a selection by boot_frequencies().
  idx <- which(!is.na(m), arr.ind = TRUE)
  reps <- data.frame(
    replicate = as.integer(idx[, "row"]),
    parameter = terms_seen[idx[, "col"]],
    estimate  = as.numeric(m[idx]),
    stringsAsFactors = FALSE
  )
  reps <- reps[order(reps$replicate, reps$parameter), , drop = FALSE]
  rownames(reps) <- NULL

  # Under select = "none" nothing is selected, so sle, sls and max_steps were
  # never consulted. Recording the defaults would print entry and stay levels
  # in the provenance table for a screen that used neither; NA prints a gap.
  selected <- !identical(ctl$method, "none")
  bag <- list(
    n_boot       = as.integer(x$n_rep),
    seed         = ctl$seed,
    slentry      = if (selected) ctl$sle else NA_real_,
    slstay       = if (selected) ctl$sls else NA_real_,
    base_params  = base_params,
    requested    = requested,
    usable       = n_usable,
    n_rows       = as.integer(ctl$n_rows),
    elapsed_mins = ctl$elapsed_mins,
    manifest     = manifest,
    # Which codebase ran, carried with the numbers. A version string alone
    # cannot say that, but its absence prints as NA in the provenance table,
    # which reads as an answer rather than as a gap.
    engine       = ctl$package,
    engine_sha   = if (is.null(ctl$sha)) NA_character_ else ctl$sha,
    # The rest of the screen's definition, so boot_pool_chunks() can check
    # that two bags ran the same screen rather than assume it. boot_select()
    # always draws rows; patient resampling is the hazard runner's.
    method       = ctl$method,
    max_steps    = if (selected) as.integer(ctl$max_steps) else NA_integer_,
    fraction     = ctl$fraction,
    resampled    = "rows",
    fitter       = ctl$fitter,
    formula      = ctl$formula,
    rng_kind     = if (is.null(ctl$rng_kind)) NA_character_ else ctl$rng_kind,
    boot         = list(
      replicates = reps,
      summary    = .bag_summary(m),
      n_success  = as.integer(x$n_rep),
      n_failed   = as.integer(x$n_attempts) - as.integer(x$n_rep)
    )
  )
  if (!is.null(dropped)) {
    bag$dropped <- dropped
  }
  # The family's shared record, carried from the run rather than rebuilt: a
  # bag built today from a screen run last week must not claim today's RNG
  # kind or time. A screen from before the record existed gets NA there.
  bag$provenance <- if (is.list(x[["provenance"]])) {
    x$provenance
  } else {
    scalar_chr <- function(v) {
      if (length(v) == 1L) as.character(v) else NA_character_
    }
    old <- .hvti_provenance(ctl$method, ctl$seed,
                            rng_kind = rep(NA_character_, 3L),
                            time = as.POSIXct(NA),
                            fitter = scalar_chr(ctl$fitter),
                            formula = scalar_chr(ctl$formula))
    old$version <- scalar_chr(ctl$package)
    old$sha <- NA_character_
    old
  }

  # Validated on the way out, so this function cannot emit a bag that the report
  # will refuse three chunks into a render.
  boot_validate(bag)
  bag
}
