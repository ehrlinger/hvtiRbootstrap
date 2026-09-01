# One value per phase, rendered as one string.
#
# A multiphase screen offers its candidate pool to each phase separately, so
# `requested` arrives as c(early = 230, late = 230). Collapsed to a labelled
# string rather than summed: that is one pool seen twice, not 460 candidates.
#
# The zero-length case must still return exactly ONE string. format(integer(0))
# is character(0), which contributes no element rather than one, so the value
# vector comes up short and data.frame() fails with the "differing number of
# rows" error this helper exists to prevent. boot_validate() now rejects a
# zero-length `requested` upstream, which makes this the second line of
# defence rather than the only one -- but format(NULL) is the string "NULL"
# while format(integer(0)) is character(0), so only the typed case actually
# drops, and guessing which a future runner writes is not a plan.
.per_phase <- function(x) {
  if (length(x) == 0L) {
    return(NA_character_)
  }
  if (length(x) == 1L) {
    return(format(x))
  }
  if (is.null(names(x))) {
    return(paste(format(x), collapse = ", "))
  }
  paste0(names(x), " ", format(x), collapse = ", ")
}

#' Where a bootstrap screen came from
#'
#' @description
#' The facts a reader needs to judge, reproduce or reject a screen: how many
#' replicates, under which entry and stay criteria, over how many candidates
#' and rows, at what cost, against which dataset and which build of the fitting
#' engine.
#'
#' @details
#' `requested` and `usable` are **per phase** on a multiphase screen, and
#' rendering them is the reason this function exists rather than a bare
#' `data.frame()` call in each report. They are collapsed to one labelled
#' string per row --
#' `"early 230, late 230"` -- and never summed: the candidate pool is *offered*
#' to each phase, so 230 and 230 is one pool seen twice rather than 460
#' candidates.
#'
#' Two facts travel with a tag that says what kind of evidence they are:
#'
#' * The **dataset checksum** is `"<algo>:<digest>"`. An md5 and a sha256 of
#'   the same file are different strings, and of different files may not be, so
#'   a bare digest recorded without its algorithm is not evidence of anything.
#' * The **fitting engine** is `"sha:<commit>"` in preference to
#'   `"version:<string>"`. One real package version existed as two codebases,
#'   one with a selection criterion and one without, and the selection
#'   criterion is precisely the thing that decides what a screen selects.
#'
#' Elapsed time is reported as **summed CPU hours**, not wall clock:
#' [boot_pool_chunks()] sums `elapsed_mins` across chunks, so on a chunked run
#' this is total compute and chunks run in parallel finish in a fraction of it.
#'
#' Seeds are summarised here and listed by [boot_seeds()]. At 25 chunks the
#' joined seed string is a single 270-character cell.
#'
#' @param bag A bootstrap screen: the object [boot_pool_chunks()] returns, or a
#'   single unchunked run of the same shape. Checked by [boot_validate()].
#'
#' @return A data frame with columns `item` and `value`, both character, one
#'   row per fact. **The row count does not depend on the shape of any field**
#'   - a per-phase `requested` yields the same rows as a scalar one.
#'
#' @seealso [boot_seeds()] for the seeds themselves, [boot_health()] for
#'   whether the screen ran, and [boot_shortfall()] for whether the pool is the
#'   run that was launched.
#'
#' @examples
#' bag <- list(
#'   n_boot = 500L, n_chunks = 2L, seed = "101, 202", seeds = c(101, 202),
#'   slentry = 0.07, slstay = 0.05, base_params = "base",
#'   requested = c(early = 230L, late = 230L),
#'   usable = c(early = 226L, late = 226L),
#'   n_rows = 4000L, elapsed_mins = 150, th_sha = "deadbeef",
#'   manifest = list(sha256 = "abc123"),
#'   boot = list(replicates = data.frame(replicate = 1L, parameter = "base",
#'                                       estimate = 1),
#'               summary = data.frame(parameter = "base", n = 1L, pct = 100),
#'               n_success = 500L, n_failed = 0L))
#' boot_provenance(bag)
#' boot_seeds(bag)
#' @export
boot_provenance <- function(bag) {
  boot_validate(bag)

  cpu_hours <- bag$elapsed_mins / 60

  checksum <- NA_character_
  for (algo in c("sha256", "md5")) {
    if (!is.null(bag$manifest[[algo]])) {
      checksum <- paste0(algo, ":", bag$manifest[[algo]])
      break
    }
  }

  engine <- if (!is.null(bag$th_sha)) {
    paste0("sha:", bag$th_sha)
  } else if (!is.null(bag$th_version)) {
    paste0("version:", bag$th_version)
  } else {
    NA_character_
  }

  n_chunks <- if (is.null(bag$n_chunks)) 1L else as.integer(bag$n_chunks)

  data.frame(
    item = c("Replicates pooled", "Chunks pooled", "Entry level (slentry)",
             "Stay level (slstay)", "Candidates offered", "Candidates usable",
             "Rows screened", "Replicates that fitted",
             "Replicates that failed", "CPU hours (summed)", "Fitting engine",
             "Dataset checksum", "Seeds"),
    value = c(format(bag$n_boot), format(n_chunks), format(bag$slentry),
              format(bag$slstay), .per_phase(bag$requested),
              .per_phase(bag$usable), format(bag$n_rows),
              format(bag$boot$n_success), format(bag$boot$n_failed),
              sprintf("%.1f", cpu_hours), engine, checksum,
              paste0(n_chunks, " distinct (listed below)")),
    stringsAsFactors = FALSE
  )
}

#' Every seed a bootstrap screen used
#'
#' @description
#' One row per chunk, so that a rerun is reproducible and a duplicate is
#' visible.
#'
#' @details
#' Two chunks sharing a seed contain literally the **same** replicates: pooling
#' them counts each twice and reports a Monte-Carlo error smaller than the run
#' actually has. [boot_pool_chunks()] refuses that outright, so a pooled screen
#' cannot reach here with a duplicate. This table is what lets you check a
#' *single* run, and what lets a reader reproduce either.
#'
#' A single unchunked run never went through [boot_pool_chunks()] and carries
#' only the scalar `seed` its runner wrote, so that is used when `seeds` is
#' absent. Seeds are formatted without scientific notation: a seed printed as
#' `1.23e+08` cannot be typed back in.
#'
#' @param bag A bootstrap screen. Checked by [boot_validate()].
#'
#' @return A data frame with columns `chunk` (integer) and `seed` (character).
#'
#' @seealso [boot_provenance()], which summarises the count.
#'
#' @examples
#' bag <- list(
#'   n_boot = 500L, seed = 4242, slentry = 0.07, slstay = 0.05,
#'   base_params = "base", requested = 230L, usable = 226L,
#'   n_rows = 4000L, elapsed_mins = 150, manifest = list(sha256 = "abc123"),
#'   boot = list(replicates = data.frame(replicate = 1L, parameter = "base",
#'                                       estimate = 1),
#'               summary = data.frame(parameter = "base", n = 1L, pct = 100),
#'               n_success = 500L, n_failed = 0L))
#' boot_seeds(bag)
#' @export
boot_seeds <- function(bag) {
  boot_validate(bag)

  seed_list <- if (!is.null(bag$seeds)) bag$seeds else bag$seed
  data.frame(
    chunk = seq_along(seed_list),
    seed  = format(seed_list, scientific = FALSE),
    stringsAsFactors = FALSE
  )
}
