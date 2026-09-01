# Shape checks. Each returns a sentence naming the field, what was expected and
# what was found, or character(0) when the field is sound. They return rather
# than stop so that boot_validate() can report every failure at once.

# Present, exactly one value, not missing.
.chk_scalar <- function(x, field) {
  if (is.null(x)) {
    return(paste0(field, ": expected a single value, found nothing"))
  }
  if (length(x) != 1L) {
    return(paste0(field, ": expected a single value, found length ",
                  length(x)))
  }
  if (is.na(x)) {
    return(paste0(field, ": expected a single value, found NA"))
  }
  character(0)
}

# Present, numeric, at least one value. A length > 1 value is VALID here: a
# multiphase screen offers its candidate pool to each phase separately and
# records one count per phase. Names are preferred and not required.
.chk_per_phase <- function(x, field) {
  if (is.null(x)) {
    return(paste0(field, ": expected one value per phase, found nothing"))
  }
  if (!is.numeric(x)) {
    return(paste0(field, ": expected a numeric value, found ", class(x)[1L]))
  }
  if (length(x) == 0L) {
    return(paste0(field, ": expected at least one value, found length 0"))
  }
  character(0)
}

# Present and carrying something. Shape is the caller's business.
.chk_any <- function(x, field) {
  if (is.null(x) || length(x) == 0L) {
    return(paste0(field, ": expected a value, found nothing"))
  }
  character(0)
}

# Present and a list, because it is indexed by name.
#
# `manifest[["sha256"]]` on a named ATOMIC vector that does not carry the name
# is not NULL -- it is an error, "subscript out of bounds", which names
# neither the field nor the file. The same indexing happens in
# boot_pool_chunks(), so this is a shape the package relies on twice.
.chk_named_list <- function(x, field) {
  present <- .chk_any(x, field)
  if (length(present)) {
    return(present)
  }
  if (!is.list(x)) {
    return(paste0(field, ": expected a list indexed by name, found ",
                  class(x)[1L]))
  }
  character(0)
}

#' Check that a bootstrap bag has the shape a report reads
#'
#' @description
#' The runner that produces a bootstrap screen is a study file, not a templated
#' one, so the fields a report reads are a contract between two files that no
#' shared function enforces. This is that function.
#'
#' @details
#' It replaces the `contract` chunk that each bootstrap report carried, and it
#' differs from that chunk in the way that matters: **it checks the shape of
#' every field it names, not merely that the name exists.** The chunk passed a
#' real bag happily while `requested` was a length-2 vector the report could not
#' render, and the resulting defect shipped in three releases.
#'
#' Three shapes are checked, because three things can be true of a field:
#'
#' * **Scalar** - `n_boot`, `seed`, `slentry`, `slstay`, `n_rows` and
#'   `elapsed_mins` are each one value. A length-2 `n_boot` means the pool was
#'   written per phase into a field that is not per phase, and every count
#'   downstream is then ambiguous.
#' * **Per phase** - `requested` and `usable` may be a vector, and on a
#'   multiphase screen they are: the candidate pool is *offered* to each phase,
#'   so `c(early = 230, late = 230)` is one pool seen twice. They must be
#'   numeric and carry at least one value. `integer(0)` satisfies "is present"
#'   and then contributes no element rather than one, which collapses any table
#'   built from it.
#' * **Any shape** - `base_params` is read whole, and `boot` must carry
#'   `replicates`, `summary`, `n_success` and `n_failed`. `boot` being present
#'   says nothing about what is inside it. `manifest` is the one exception:
#'   it must be a **list**, because it is indexed by name, and
#'   `manifest[["sha256"]]` on a named atomic vector lacking that name is not
#'   `NULL` but an error -- `subscript out of bounds`, naming neither the
#'   field nor the file.
#'
#' Every failure is reported at once. An author fixing a runner wants the whole
#' list; one at a time turns a single fix into five renders.
#'
#' `dropped`, `free_sd`, `n_chunks`, `seeds` and the engine provenance fields
#' are **not** required. A single unchunked run legitimately carries none of
#' them, and [boot_provenance()], [boot_health()] and [boot_dropped()] each say
#' what they do in their absence.
#'
#' @param bag A bootstrap screen: the object [boot_pool_chunks()] returns, or a
#'   single unchunked run of the same shape.
#'
#' @return `invisible(TRUE)`. Called for the error it raises otherwise.
#'
#' @seealso [boot_provenance()], [boot_frequencies()], [boot_concepts()] and
#'   [boot_health()], each of which calls this first; [boot_shortfall()] for
#'   the different question of whether the pool is the run that was launched.
#'
#' @examples
#' bag <- list(
#'   n_boot = 4L, seed = 101, slentry = 0.07, slstay = 0.05,
#'   base_params = "base", requested = 4L, usable = 3L,
#'   n_rows = 500L, elapsed_mins = 120, manifest = list(sha256 = "abc123"),
#'   boot = list(
#'     replicates = data.frame(replicate = c(1L, 2L),
#'                             parameter = c("early.age", "early.age"),
#'                             estimate = c(0.5, 0.6)),
#'     summary = data.frame(parameter = "early.age", n = 2L, pct = 50),
#'     n_success = 4L, n_failed = 0L))
#' boot_validate(bag)
#'
#' # A per-phase `requested` is valid, not a defect: the pool is offered to
#' # each phase, so this is one pool seen twice.
#' bag$requested <- c(early = 230L, late = 230L)
#' boot_validate(bag)
#'
#' # A per-phase `n_boot` is a defect, and this is the shape that shipped.
#' bag$n_boot <- c(500L, 500L)
#' try(boot_validate(bag))
#' @export
boot_validate <- function(bag) {
  if (!is.list(bag)) {
    stop("`bag` must be a list: the bootstrap screen itself, not a path to ",
         "it. Read it with `readRDS()` first, or pool the chunks with ",
         "`boot_pool_chunks()`.", call. = FALSE)
  }

  scalars <- c("n_boot", "seed", "slentry", "slstay", "n_rows", "elapsed_mins")
  problems <- c(
    unlist(lapply(scalars, function(f) .chk_scalar(bag[[f]], f)),
           use.names = FALSE),
    unlist(lapply(c("requested", "usable"),
                  function(f) .chk_per_phase(bag[[f]], f)),
           use.names = FALSE),
    .chk_any(bag$base_params, "base_params"),
    .chk_named_list(bag$manifest, "manifest")
  )

  # Guarded rather than folded into the loop above: with `boot` absent there is
  # nothing to index, and reporting four nested fields it could not have looked
  # at sends the reader hunting for four problems that are one.
  nested <- c("replicates", "summary", "n_success", "n_failed")
  if (is.null(bag$boot)) {
    problems <- c(problems,
                  "boot: expected the results list, found nothing")
  } else if (!is.list(bag$boot)) {
    problems <- c(problems,
                  paste0("boot: expected a list, found ", class(bag$boot)[1L]))
  } else {
    problems <- c(problems,
                  unlist(lapply(nested, function(f) {
                    .chk_any(bag$boot[[f]], paste0("boot$", f))
                  }), use.names = FALSE))
  }

  if (length(problems)) {
    stop("This bootstrap screen does not have the shape a report reads. ",
         length(problems), " problem(s):\n",
         paste0("  - ", problems, collapse = "\n"),
         "\nEither the runner that wrote it predates these fields, or it is ",
         "not the runner this report expects. Reporting over it would print ",
         "blanks where the screen's criteria belong.", call. = FALSE)
  }

  invisible(TRUE)
}
