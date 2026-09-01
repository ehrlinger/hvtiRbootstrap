# The replicate table, pivoted from the long form a runner writes to the wide
# form boot_summary() and boot_clusters() read: one ROW per replicate, one
# COLUMN per term, an unselected term left NA.
#
# THE ROW COUNT IS n_boot, NOT THE NUMBER OF IDS PRESENT. A replicate in which
# nothing outside the base model was selected writes no rows at all, so
# counting the ids that appear would use a smaller denominator and inflate
# every frequency in the report.
#
# NA is left NA. It is the whole design: boot_summary() counts non-missing
# values down a column, so `n` IS the number of replicates that chose the term.
.replicate_matrix <- function(bag) {
  reps <- bag$boot$replicates
  if (!is.data.frame(reps) ||
        !all(c("replicate", "parameter", "estimate") %in% names(reps))) {
    stop("`bag$boot$replicates` must be a data frame with replicate, ",
         "parameter and estimate columns.", call. = FALSE)
  }
  n_boot <- as.integer(bag$n_boot)

  # boot_pool_chunks() checks this for the chunks it stacks; a single
  # unchunked run has never been through it. An out-of-range id does not
  # error on its own -- it lands on another replicate's row, and the only
  # symptom is a frequency that is slightly too low.
  if (nrow(reps) &&
        (min(reps$replicate) < 1L || max(reps$replicate) > n_boot)) {
    stop("This screen reports n_boot = ", n_boot, " but its replicate ids ",
         "run ", min(reps$replicate), "..", max(reps$replicate),
         ". Counting them would put one replicate's selections on another's ",
         "row and understate every frequency.", call. = FALSE)
  }

  terms <- sort(unique(reps$parameter))
  m <- matrix(NA_real_, nrow = n_boot, ncol = length(terms),
              dimnames = list(NULL, terms))
  m[cbind(reps$replicate, match(reps$parameter, terms))] <- reps$estimate
  m
}

# The caller's rule, applied one term at a time. `bh` passes a vectorised
# sub(), but a rule written for a single term must not silently return one
# phase for the whole screen.
.phase_of <- function(terms, phase) {
  vapply(terms, phase, character(1), USE.NAMES = FALSE)
}

# The term with its phase label removed, so that `early.age` reads as `age`.
#
# Derived from what the caller's own rule returned rather than from a
# hardcoded separator: a logistic screen has no phases and a future model
# family may build its terms differently. When the phase is not the head of
# the term there is nothing to strip and the term stands as the variable.
.variable_of <- function(terms, phases) {
  out <- terms
  for (i in seq_along(terms)) {
    ph <- phases[i]
    if (is.na(ph) || !nzchar(ph) || !startsWith(terms[i], ph)) next
    rest <- sub("^[^[:alnum:]]", "", substring(terms[i], nchar(ph) + 1L))
    if (nzchar(rest)) out[i] <- rest
  }
  out
}

#' Selection frequencies, with the error they carry
#'
#' @description
#' How often each candidate term survived selection, and how much of that
#' figure is noise.
#'
#' @details
#' A selection frequency is an **estimate**, not a count of something fixed. It
#' carries Monte-Carlo error of roughly `sqrt(p(1 - p) / n_boot)`, which at
#' `p = 0.5` over 500 replicates is about 2.2 percentage points -- so a
#' variable sitting within a few points of the retention cutoff can fall on
#' either side of it on resampling noise alone.
#'
#' `mc_error` is computed **per variable**, not once for the table. The error
#' is largest at `p = 0.5` and shrinks towards either end, so a single quoted
#' value overstates it for the variables at the top and understates it in the
#' middle -- and the middle is where the retention decision is being made.
#'
#' `n` and `pct` come from [boot_summary()], which is the function held to
#' exact parity with `%SUMBOOT`. They are not recomputed here: a second
#' implementation of the selection count is the one thing this package cannot
#' afford. What this function adds is the error, the cutoff and the optional
#' phase grouping.
#'
#' **The base parameters are dropped.** They are in every replicate by
#' construction, and reporting them at 100% invites them to be read as the
#' screen's most reliable findings.
#'
#' @param bag A bootstrap screen. Checked by [boot_validate()].
#' @param phase A function mapping a term to its phase, or `NULL`. With `NULL`
#'   there is no phase dimension and no `phase` column. A multiphase hazard
#'   screen passes `function(term) sub("[.].*$", "", term)`, which reads
#'   `early.age` as the early phase's decision about `age`; a logistic, linear
#'   or Cox screen has no phases and passes nothing. The rule is applied one
#'   term at a time, so it need not be vectorised, and `variable` is the term
#'   with the returned phase label stripped from its head when it is there.
#' @param threshold The retention cutoff, as a percentage, or `NULL`. This is a
#'   **reporting** decision and not something the run recorded: `slentry` and
#'   `slstay` governed each replicate's stepwise fit, and neither says how
#'   often a variable must survive to be worth carrying forward.
#'
#' @return A data frame with columns `variable`, `term`, `n`, `pct`,
#'   `mc_error`, `near_threshold` and `retained`, plus `phase` when `phase` is
#'   supplied. `term` is the name as the screen recorded it and `variable` the
#'   same name without its phase; they are identical when there is no phase
#'   rule. `near_threshold` marks a term within two Monte-Carlo errors of the
#'   cutoff -- retention that would not survive a rerun with different seeds --
#'   and both it and `retained` are `NA` when no `threshold` is given, because
#'   with no cutoff there is no retention decision to make a claim about.
#'
#' @seealso [boot_summary()], which computes the counts; [boot_concepts()] for
#'   the same frequencies grouped by concept; [boot_dropped()] for the
#'   candidates that never reached a replicate at all.
#'
#' @examples
#' bag <- list(
#'   n_boot = 4L, seed = 101, slentry = 0.07, slstay = 0.05,
#'   base_params = "base", requested = 4L, usable = 3L, n_rows = 500L,
#'   elapsed_mins = 120, manifest = list(sha256 = "abc123"),
#'   boot = list(
#'     replicates = data.frame(
#'       replicate = c(1L, 1L, 2L, 3L, 4L),
#'       parameter = c("base", "early.age", "early.age", "base", "late.bmi"),
#'       estimate  = c(1, 0.5, 0.6, 0.9, 0.2)),
#'     summary = data.frame(parameter = "base", n = 2L, pct = 50),
#'     n_success = 4L, n_failed = 0L))
#'
#' boot_frequencies(bag)
#'
#' # A multiphase screen passes its own term-splitting rule.
#' boot_frequencies(bag, phase = function(term) sub("[.].*$", "", term),
#'                  threshold = 50)
#' @export
boot_frequencies <- function(bag, phase = NULL, threshold = NULL) {
  boot_validate(bag)
  if (!is.null(phase) && !is.function(phase)) {
    stop("`phase` must be a function mapping a term to its phase, or NULL.",
         call. = FALSE)
  }
  if (!is.null(threshold) &&
        (!is.numeric(threshold) || length(threshold) != 1L ||
           is.na(threshold))) {
    stop("`threshold` must be a single retention percentage, or NULL.",
         call. = FALSE)
  }

  summ <- boot_summary(.replicate_matrix(bag))
  out <- data.frame(variable = summ$variable, term = summ$variable,
                    n = summ$n, pct = summ$pct, stringsAsFactors = FALSE)
  out <- out[!out$term %in% bag$base_params, , drop = FALSE]

  p <- out$pct / 100
  out$mc_error <- 100 * sqrt(p * (1 - p) / as.integer(bag$n_boot))
  # NA rather than FALSE with no cutoff supplied: FALSE is the claim "this
  # retention is stable", and there is no retention decision to be stable
  # about. rep() rather than a bare NA so that an empty screen still assigns.
  out$near_threshold <- if (is.null(threshold)) {
    rep(NA, nrow(out))
  } else {
    abs(out$pct - threshold) <= 2 * out$mc_error
  }
  out$retained <- if (is.null(threshold)) {
    rep(NA, nrow(out))
  } else {
    out$pct >= threshold
  }

  if (is.null(phase)) {
    out <- out[order(-out$pct, out$variable), , drop = FALSE]
  } else {
    ph <- .phase_of(out$term, phase)
    out$variable <- .variable_of(out$term, ph)
    out$phase <- ph
    out <- out[order(out$phase, -out$pct, out$variable), , drop = FALSE]
    out <- out[, c("phase", setdiff(names(out), "phase")), drop = FALSE]
  }
  rownames(out) <- NULL
  out
}

#' Candidates the screen never saw
#'
#' @description
#' The candidates a runner dropped before screening, with the reason each was
#' dropped.
#'
#' @details
#' A candidate the screen never saw **cannot appear at any frequency**, so its
#' absence from [boot_frequencies()] is indistinguishable from never having
#' been selected. That is the whole reason this table exists: without it, a
#' constant column and a genuinely unselected variable read the same way.
#'
#' Whatever columns the runner wrote are kept. Rows are ordered by `phase` and
#' then `reason` when those columns are present, so that a reader meets whole
#' classes of dropped candidate together rather than scattered down a table
#' that runs to dozens of rows on a real pool.
#'
#' Unlike [boot_frequencies()] and [boot_concepts()] this takes **no `phase`
#' argument.** `bag$dropped` carries its own `phase` column, written by the
#' runner that did the dropping, so there is nothing for a term-splitting rule
#' to do; a candidate dropped before screening never became a model term.
#'
#' `dropped` is not a required field. A runner that drops nothing may not write
#' it at all, and that is reported as no rows rather than as a fault.
#'
#' @param bag A bootstrap screen. Checked by [boot_validate()].
#'
#' @return A data frame of the dropped candidates, with no rows when nothing
#'   was dropped.
#'
#' @seealso [boot_frequencies()] for the candidates that were screened.
#'
#' @examples
#' bag <- list(
#'   n_boot = 4L, seed = 101, slentry = 0.07, slstay = 0.05,
#'   base_params = "base", requested = 4L, usable = 3L, n_rows = 500L,
#'   elapsed_mins = 120, manifest = list(sha256 = "abc123"),
#'   dropped = data.frame(variable = c("zexp", "agee"),
#'                        phase = c("late", "early"),
#'                        reason = c("constant", "all missing")),
#'   boot = list(
#'     replicates = data.frame(replicate = 1L, parameter = "base",
#'                             estimate = 1),
#'     summary = data.frame(parameter = "base", n = 1L, pct = 25),
#'     n_success = 4L, n_failed = 0L))
#' boot_dropped(bag)
#' @export
boot_dropped <- function(bag) {
  boot_validate(bag)

  d <- bag$dropped
  if (is.null(d)) {
    return(data.frame(variable = character(0), phase = character(0),
                      reason = character(0), stringsAsFactors = FALSE))
  }
  if (!is.data.frame(d)) {
    stop("`bag$dropped` must be a data frame of dropped candidates, or ",
         "absent.", call. = FALSE)
  }
  if (!nrow(d)) {
    return(d)
  }

  by <- intersect(c("phase", "reason"), names(d))
  if (length(by)) {
    d <- d[do.call(order, unname(as.list(d[, by, drop = FALSE]))), ,
           drop = FALSE]
  }
  rownames(d) <- NULL
  d
}
