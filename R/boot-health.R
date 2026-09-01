#' Did the bootstrap screen actually run?
#'
#' @description
#' Four facts about a screen, two of which are checks that catch a run which
#' produced a perfectly ordinary-looking table of numbers that mean nothing.
#'
#' @details
#' **A screen that selected nothing is a failure, not a finding.** It is the
#' signature of a formula that did not survive the per-replicate rewrite: the
#' refit errors, the error is caught, the step reports nothing accepted, and
#' the screen halts having selected nothing -- with no warning and
#' `n_failed = 0`. The summary then reads as a table of perfectly reliable
#' variables. Absence from a frequency table cannot say this; a row that says
#' `ok = FALSE` can.
#'
#' **A free base parameter must vary across resamples.** A bootstrap built on
#' a vector interface returns the original fit every replicate, with
#' `n_success = 500`, `n_failed = 0` and no warning at all. The standard
#' deviation of the first free base parameter is the only tell, and a value of
#' exactly zero is that failure. It is `NA`, never `0`, when there is nothing
#' to take a standard deviation of: zero is the *claim* that the parameter did
#' not vary, and one replicate cannot support it.
#'
#' `free_sd` is recomputed when the screen does not carry it. Only
#' [boot_pool_chunks()] writes that field, so a single unchunked run has
#' none -- and an unchunked run is the shape most likely to have been built the
#' way this check exists to catch. Skipping it there would turn the check off
#' in exactly the case that needs it.
#'
#' This function **returns** its findings rather than stopping. A report
#' decides how to present them: a callout, a red cell, or a `stop()` of its
#' own.
#'
#' @param bag A bootstrap screen. Checked by [boot_validate()].
#'
#' @return A data frame with one row per check and columns `check`, `value`,
#'   `ok` and `note`. `ok` is `FALSE` for a failed check, `TRUE` for a passed
#'   one, and `NA` for a row that is a fact rather than a check. `note` says
#'   what a failure means and is `NA` otherwise.
#'
#' @seealso [boot_provenance()] for where the screen came from, and
#'   [boot_shortfall()] for whether the pool is the run that was launched --
#'   a different question, and one nothing inside a chunk can answer.
#'
#' @examples
#' bag <- list(
#'   n_boot = 4L, seed = 101, slentry = 0.07, slstay = 0.05,
#'   base_params = "base", requested = 4L, usable = 3L, n_rows = 500L,
#'   elapsed_mins = 120, manifest = list(sha256 = "abc123"),
#'   boot = list(
#'     replicates = data.frame(
#'       replicate = c(1L, 1L, 2L, 3L, 4L),
#'       parameter = c("base", "early.age", "base", "base", "base"),
#'       estimate  = c(1, 0.5, 1.1, 0.9, 1.2)),
#'     summary = data.frame(parameter = "base", n = 4L, pct = 100),
#'     n_success = 4L, n_failed = 0L))
#' boot_health(bag)
#'
#' # A screen that selected nothing outside the base model.
#' bag$boot$replicates <- bag$boot$replicates[-2, ]
#' boot_health(bag)
#' @export
boot_health <- function(bag) {
  boot_validate(bag)

  reps <- bag$boot$replicates
  candidates <- setdiff(unique(reps$parameter), bag$base_params)

  free_sd <- if (!is.null(bag$free_sd)) {
    bag$free_sd
  } else {
    est <- reps$estimate[reps$parameter == bag$base_params[[1L]]]
    if (length(est) > 1L) stats::sd(est) else NA_real_
  }

  n_success <- as.integer(bag$boot$n_success)

  empty_note <- paste0(
    "The screen selected NOTHING: no parameter outside the base model ",
    "appears in any replicate. That is a failed screen, not a null result. ",
    "It is what a model formula held in a variable looks like from here -- ",
    "the per-replicate refit errors, the error is caught, and the step ",
    "simply accepts nothing, so n_failed is 0. Write the formula literally ",
    "at the call site in the runner and rerun."
  )
  # "same fit" appears verbatim in the test for this note: it is the claim
  # the check makes, and the sentence is what a study author will read.
  flat_note <- paste0(
    "The first free base parameter has a standard deviation of exactly 0, ",
    "so every replicate returned the same fit. A bootstrap built on a ",
    "vector interface does that: it refits nothing and reports every ",
    "replicate as a success, with no warning. The frequencies would all be ",
    "100% and mean nothing."
  )

  data.frame(
    check = c("Replicates that fitted", "Replicates that failed",
              "Distinct candidates ever selected",
              "SD of the first free base parameter"),
    value = c(format(bag$boot$n_success), format(bag$boot$n_failed),
              format(length(candidates)), format(free_sd)),
    # A nonzero failure count is not itself a fault -- %bootreg redraws a
    # failed replicate without counting it -- so that row is a fact, not a
    # check, and says NA rather than passing something it did not test.
    ok = c(!is.na(n_success) & n_success > 0L,
           NA,
           length(candidates) > 0L,
           if (is.na(free_sd)) NA else free_sd != 0),
    note = c(NA_character_, NA_character_,
             if (length(candidates)) NA_character_ else empty_note,
             if (!is.na(free_sd) && free_sd == 0) flat_note else NA_character_),
    stringsAsFactors = FALSE
  )
}
