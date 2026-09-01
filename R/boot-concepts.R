#' Selection frequencies grouped by concept
#'
#' @description
#' A per-form selection frequency answers "how often was *this form* selected".
#' It cannot answer "how often was *this concept* selected", and that is the
#' number a paper quotes.
#'
#' @details
#' The gap runs both ways. Competing forms split replicates between them, so a
#' concept reads weaker than any single figure suggests; or two forms both
#' clear the cutoff and one finding is reported twice.
#'
#' **`pct_any` is not a sum**, for the same reason [boot_clusters()]'s `n_any`
#' is not: a replicate that selected two forms of one concept counts **once**.
#' Two forms at 30% each are anywhere between 30% and 60% of replicates
#' depending entirely on how often the same replicate took both, and no
#' marginal percentage records that -- so this is computed from the replicate
#' table, never from the summary. The computation is [boot_clusters()]'s,
#' called rather than repeated.
#'
#' `spread` is `pct_any - best_form_pct`: how much the per-form view
#' understates the concept. A spread of zero means the concept has one form and
#' the two views agree.
#'
#' `n_retained` is the crowding number. A phase that spent several of its slots
#' on forms of **one** concept is budget-limited by redundancy, and that is
#' invisible in a coefficient table; the concepts where `n_retained > 1` are
#' the crowded ones.
#'
#' **Nothing here collapses [boot_frequencies()].** Every form keeps its own row
#' and its own frequency there, because two forms of one concept may carry
#' different information: on one real pool, `in_zexp` **is** `1/zexp` and yet
#' correlates with `zexp` at only -0.195, because `zexp` spans a 4000-fold
#' range. That study's published model uses both, in the same phase, both
#' significant. This table is an additional view, not a replacement.
#'
#' @param bag A bootstrap screen. Checked by [boot_validate()].
#' @param concept_map A data frame with columns `variable` and `concept`,
#'   mapping each screened variable to the concept it is a form of. This is the
#'   **study's own vocabulary** and is received, never inferred: which names
#'   are forms of one thing is a fact about an institution's naming
#'   conventions, not about statistics. A variable the map does not name is
#'   treated as a concept of its own rather than dropped, so nothing leaves the
#'   concept view silently.
#' @param phase A function mapping a term to its phase, or `NULL`. As in
#'   [boot_frequencies()]: with `NULL` there is no phase dimension, and the
#'   `concept_map` is then keyed on whole terms rather than phase-stripped
#'   names.
#' @param threshold The retention cutoff, as a percentage, or `NULL`.
#'
#' @return A data frame with one row per concept -- per concept per phase when
#'   `phase` is supplied -- with columns `concept`, `n_forms`, `forms`,
#'   `n_any`, `pct_any`, `best_form_pct`, `spread`, `n_retained` and
#'   `retained`, plus `phase`. `n_retained` and `retained` are `NA` when no
#'   `threshold` is given.
#'
#' @seealso [boot_frequencies()] for the per-form view this groups, and
#'   [boot_clusters()] for the same at-least-one count over a group named by
#'   declaration rather than by name.
#'
#' @examples
#' bag <- list(
#'   n_boot = 4L, seed = 101, slentry = 0.07, slstay = 0.05,
#'   base_params = "base", requested = 4L, usable = 3L, n_rows = 500L,
#'   elapsed_mins = 120, manifest = list(sha256 = "abc123"),
#'   boot = list(
#'     replicates = data.frame(
#'       replicate = c(1L, 1L, 1L, 2L, 2L, 3L, 3L, 4L),
#'       parameter = c("base", "early.age", "early.ln_age",
#'                     "base", "early.age", "base", "early.ln_age", "base"),
#'       estimate  = c(1, 0.5, 0.4, 1.1, 0.6, 0.9, 0.3, 1.2)),
#'     summary = data.frame(parameter = "base", n = 4L, pct = 100),
#'     n_success = 4L, n_failed = 0L))
#'
#' map <- data.frame(variable = c("age", "ln_age"), concept = c("Age", "Age"))
#'
#' # Both forms sit at 50%, and replicate 1 took both -- so the concept is at
#' # 75%, not 100%.
#' boot_concepts(bag, map, phase = function(term) sub("[.].*$", "", term))
#' @export
boot_concepts <- function(bag, concept_map, phase = NULL, threshold = NULL) {
  freq <- boot_frequencies(bag, phase = phase, threshold = threshold)

  if (!is.data.frame(concept_map)) {
    stop("`concept_map` must be a data frame with `variable` and `concept` ",
         "columns. It is the study's vocabulary, and this function receives ",
         "it rather than inferring one.", call. = FALSE)
  }
  need <- setdiff(c("variable", "concept"), names(concept_map))
  if (length(need)) {
    stop("`concept_map` is missing the column(s): ",
         paste(need, collapse = ", "), ".", call. = FALSE)
  }

  cols <- c("concept", "n_forms", "forms", "n_any", "pct_any",
            "best_form_pct", "spread", "n_retained", "retained")
  empty <- data.frame(concept = character(0), n_forms = integer(0),
                      forms = character(0), n_any = integer(0),
                      pct_any = numeric(0), best_form_pct = numeric(0),
                      spread = numeric(0), n_retained = integer(0),
                      retained = logical(0), stringsAsFactors = FALSE)
  if (!is.null(phase)) {
    empty <- cbind(phase = character(0), empty, stringsAsFactors = FALSE)
  }
  if (!nrow(freq)) {
    return(empty)
  }

  con <- concept_map$concept[match(freq$variable, concept_map$variable)]
  con[is.na(con)] <- freq$variable[is.na(con)]
  freq$concept <- as.character(con)

  # Grouped by matching whole key rows rather than by pasting them into one
  # string. Both plausible separators -- "." and " " -- occur in real variable
  # names, and a separator collision here would merge two concepts into one
  # row with a union that is neither of them.
  keep <- if (is.null(phase)) "concept" else c("phase", "concept")
  idx <- freq[, keep, drop = FALSE]
  uk <- unique(idx)
  rownames(uk) <- NULL
  g <- rep(NA_integer_, nrow(idx))
  for (i in seq_len(nrow(uk))) {
    hit <- rep(TRUE, nrow(idx))
    for (cn in names(uk)) hit <- hit & idx[[cn]] == uk[[cn]][i]
    g[is.na(g) & hit] <- i
  }

  # The at-least-one count is boot_clusters()'s, called rather than repeated.
  # Synthetic group names, because a concept name is not unique across phases
  # and boot_clusters() refuses a duplicated name.
  members <- split(freq$term, g)
  names(members) <- paste0("g", names(members))
  cl <- boot_clusters(.replicate_matrix(bag), members)
  cl <- cl[match(paste0("g", seq_len(nrow(uk))), cl$cluster), , drop = FALSE]

  out <- uk
  out$n_forms <- as.integer(tabulate(g, nbins = nrow(uk)))
  out$forms <- vapply(seq_len(nrow(uk)), function(i) {
    paste(sort(freq$variable[g == i]), collapse = ", ")
  }, character(1))
  out$n_any <- cl$n_any
  out$pct_any <- cl$pct_any
  out$best_form_pct <- vapply(seq_len(nrow(uk)), function(i) {
    max(freq$pct[g == i])
  }, numeric(1))
  out$spread <- out$pct_any - out$best_form_pct
  # sum() over an all-NA logical is NA, so with no threshold this is NA
  # without a special case -- and NA is right: nothing was retained or not
  # retained, because no cutoff was applied.
  out$n_retained <- vapply(seq_len(nrow(uk)), function(i) {
    sum(freq$retained[g == i])
  }, integer(1))
  out$retained <- if (is.null(threshold)) {
    rep(NA, nrow(uk))
  } else {
    out$pct_any >= threshold
  }

  ord <- if (is.null(phase)) {
    order(-out$pct_any, out$concept)
  } else {
    order(out$phase, -out$pct_any, out$concept)
  }
  out <- out[ord, c(setdiff(names(out), cols), cols), drop = FALSE]
  rownames(out) <- NULL
  out
}
