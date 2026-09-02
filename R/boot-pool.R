# Pooling chunked bootstrap runs into one screen.
#
# WHY CHUNKS EXIST. A bootstrap screen that writes nothing until its last
# replicate finishes is unrestartable: a run that dies at 90% -- reboot,
# session cleanup, OOM -- yields nothing. On one real study a single forward
# selection over 160 candidates per phase was still running at 22 minutes and
# the job did 501 of them. Chunking makes such a run restartable, and gives a
# usable answer after the first chunk lands.
#
# WHY POOLING IS LEGITIMATE. A bootstrap replicate is an iid draw from the same
# resampling distribution, so five runs of 100 pool into the same thing as one
# run of 500 -- PROVIDED every chunk drew from the same data, ran the same
# screen, and no two used the same seed. Each of those is checked rather than
# assumed, because none of them fails loudly on its own.

# The chunk's dataset checksum, as "<algo>:<digest>", or NULL if it records
# none.
#
# WHY THE COLUMN NAME IS NOT HARD-CODED. A manifest writer moving from md5
# to
# sha256 leaves chunks of both vintages side by side. Reading one fixed column
# would return NULL for every chunk of the other vintage -- which, before the
# absence check in agree(), passed as unanimous agreement. The gate would have
# gone quiet at exactly the moment the manifest changed.
#
# WHY THE ALGORITHM TRAVELS WITH THE DIGEST. An md5 and a sha256 of the same
# file are different strings, and of different files may not be. Comparing bare
# digests across algorithms compares things that are not comparable.
.chunk_checksum <- function(k) {
  m <- k[["manifest"]]
  if (is.null(m)) return(NULL)
  for (algo in c("sha256", "md5")) {
    if (!is.null(m[[algo]])) return(paste0(algo, ":", m[[algo]]))
  }
  NULL
}

# Which build of the fitting engine produced a chunk, as "sha:<commit>" or
# "version:<string>".
#
# WHY A VERSION STRING IS NOT ENOUGH. One real package version existed as two
# different codebases -- `main` without a selection criterion, `dev` with it --
# and the selection criterion is precisely the thing that decides what a screen
# selects. A chunk recording only the version cannot say which ran.
#
# The tag travels with the value for the same reason it does on the checksum: a
# sha and a version are different KINDS of evidence, and a chunk that can name
# its commit must not be pooled with one that cannot, even when both report the
# same version.
.chunk_engine_provenance <- function(k) {
  if (!is.null(k[["th_sha"]]))     return(paste0("sha:", k[["th_sha"]]))
  if (!is.null(k[["th_version"]])) {
    return(paste0("version:", k[["th_version"]]))
  }
  NULL
}

#' Pool chunked bootstrap runs into one screen
#'
#' @description
#' Folds a list of chunk objects into a single object of the same shape, so a
#' report reads a pooled screen and a single-run screen the same way.
#'
#' @details
#' Six things must agree for chunks to be draws from one screen, and each is
#' checked rather than assumed. **None of them fails loudly on its own:**
#'
#' * Two chunks sharing a **seed** contain literally the same replicates.
#'   Pooling them counts each twice, halves nothing, and reports a Monte-Carlo
#'   error smaller than the run actually has.
#' * A **dataset rewritten mid-run** gives chunks that each look fine and
#'   describe different cohorts.
#' * A different **step cap** changes the screen, not just its cost: under a
#'   tighter cap a variable that would have entered late never gets the chance.
#'
#' Neither shows up as an error in a frequency table. Both show up as a slightly
#' different number.
#'
#' **Absence is checked before agreement, and that order is the whole point.** A
#' field no chunk records formats identically in every chunk, so it passes
#' unanimously and the accessor hands back `NULL` as the agreed value. A gate
#' that cannot tell "everyone agrees" from "nobody recorded it" is not a gate,
#' and it is worse than having none, because it reads as a check that happened.
#' This was not hypothetical: `max_steps` was absent from every chunk in one
#' test fixture and the suite was green.
#'
#' Replicate ids run `1..n_boot` **inside** each chunk, so they collide across
#' chunks and are offset before stacking. Without that, replicate 1 of chunk 2
#' merges into replicate 1 of chunk 1 and a variable selected in both counts
#' once instead of twice — understating every frequency, in a table that looks
#' entirely ordinary.
#'
#' The pooled summary is **recomputed from the pooled replicates**, never
#' averaged across chunks: a percentage of a percentage is not a percentage of
#' the whole, and the chunks need not be the same size.
#'
#' @param chunks A list of chunk objects, each carrying at least `seed`,
#'   `n_boot`, `slentry`, `slstay`, `base_params`, `usable`, `max_steps`,
#'   `elapsed_mins`, a `manifest` with an `md5` or `sha256`, an engine
#'   provenance field (`th_sha` or `th_version`), and a `boot` list with
#'   `replicates`, `n_success` and `n_failed`.
#'
#' @return One object shaped like a single chunk, with `boot$replicates` stacked
#'   and re-indexed, `boot$summary` recomputed, and `n_chunks`, `seeds` and a
#'   joined `seed` string added.
#'
#' @seealso [boot_chunk_files()] to find them, [boot_shortfall()] to check the
#'   pool is the run that was launched, and [boot_summary()] for the
#'   per-variable frequencies.
#'
#' @export
boot_pool_chunks <- function(chunks) {
  if (!length(chunks)) {
    stop("boot_pool_chunks(): no chunks to pool.", call. = FALSE)
  }

  # format() then collapse, so the comparison works for scalars and vectors
  # alike and does not depend on identical() being true of attributes.
  agree <- function(get, what) {
    vals   <- lapply(chunks, get)
    absent <- vapply(vals, is.null, logical(1))

    if (all(absent)) {
      stop("boot_pool_chunks(): no chunk records ", what, ", so it cannot be ",
           "checked. These chunks predate that field or came from a ",
           "different runner. They must not be pooled on the strength of a ",
           "check that did not happen.", call. = FALSE)
    }
    if (any(absent)) {
      stop("boot_pool_chunks(): ", sum(absent), " of ", length(chunks),
           " chunks do not record ", what, ", so they cannot be compared ",
           "with the ones that do.", call. = FALSE)
    }

    # A printable separator. The comparison works with any separator, but the
    # joined string is also what the error message prints, and a literal
    # carriage return there overwrites the line in some terminals -- so the
    # mismatch this exists to show becomes the thing you cannot read.
    txt <- vapply(vals, function(v) paste(format(v), collapse = " | "),
                  character(1))
    if (length(unique(txt)) > 1L) {
      stop("boot_pool_chunks(): the chunks disagree on ", what, " (",
           paste(unique(txt), collapse = " / "),
           "). They are not draws from the same screen and must not be pooled.",
           call. = FALSE)
    }
    vals[[1]]
  }

  # The checksum first: it is the one that means the cohort itself changed.
  agree(.chunk_checksum, "the dataset checksum")
  agree(function(k) k[["slentry"]],     "slentry")
  agree(function(k) k[["slstay"]],      "slstay")
  agree(function(k) k[["base_params"]], "the base model parameters")
  agree(function(k) k[["usable"]],      "the usable candidate counts")
  agree(.chunk_engine_provenance,  "the fitting engine version")
  agree(function(k) k[["max_steps"]],   "the step cap (max_steps)")

  seeds <- vapply(chunks, function(k) as.numeric(k[["seed"]]), numeric(1))
  if (anyDuplicated(seeds)) {
    stop("boot_pool_chunks(): two chunks share the seed ",
         paste(unique(seeds[duplicated(seeds)]), collapse = ", "),
         ". Same seed means the SAME replicates, so pooling would count them ",
         "twice and understate the Monte-Carlo error.", call. = FALSE)
  }

  # The offset arithmetic below is only sound if `replicate` really does run
  # within 1..n_boot in every chunk. Checked rather than trusted: an id outside
  # that range does not error, it lands on top of a neighbouring chunk's
  # replicate, and the only symptom is a frequency that is slightly too low.
  for (i in seq_along(chunks)) {
    r <- chunks[[i]]$boot$replicates
    if (!is.data.frame(r) ||
          !all(c("replicate", "parameter", "estimate") %in% names(r))) {
      stop("boot_pool_chunks(): chunk ", i, " has no boot$replicates data ",
           "frame with replicate/parameter/estimate columns.", call. = FALSE)
    }
    n_i <- as.integer(chunks[[i]]$n_boot)
    if (!nrow(r)) next
    if (min(r$replicate) < 1L || max(r$replicate) > n_i) {
      stop("boot_pool_chunks(): chunk ", i, " reports n_boot = ", n_i,
           " but its replicate ids run ", min(r$replicate), "..",
           max(r$replicate), ". Stacking them would overlap the neighbouring ",
           "chunk and understate every frequency.", call. = FALSE)
    }
  }

  n_each <- vapply(chunks, function(k) as.integer(k[["n_boot"]]), integer(1))
  offset <- cumsum(c(0L, n_each))
  reps <- do.call(rbind, lapply(seq_along(chunks), function(i) {
    r <- chunks[[i]]$boot$replicates
    r$replicate <- r$replicate + offset[i]
    r$chunk <- i
    r
  }))
  n_boot <- sum(n_each)

  # Hoisted ahead of .bag_summary() so that call reads a REAL bag rather than
  # a hand-built stand-in. .replicate_matrix() reads exactly $boot$replicates
  # and $n_boot today, so a stub carrying only those two matched it -- but a
  # stub is not a bag, and the day .replicate_matrix() reads a third field
  # this call would hand it NULL silently, with its error blaming a bag that
  # does not exist.
  out <- chunks[[1]]
  out$boot$replicates <- reps
  out$n_boot <- n_boot

  # The same constructor boot_bag() uses, so the pooled and unpooled shapes
  # cannot drift apart. It also gets the pooling property this block used to
  # state for itself: `n` and `pct` are recomputed from the pooled replicates
  # rather than averaged across chunks, because a percentage of a percentage is
  # not a percentage of the whole and the chunks need not be the same size.
  summ <- .bag_summary(.replicate_matrix(out))

  base_params <- chunks[[1]][["base_params"]]
  free_est <- reps$estimate[reps$parameter == base_params[1]]

  n_ok   <- vapply(chunks,
                   function(k) as.integer(k[["boot"]][["n_success"]]),
                   integer(1))
  n_bad  <- vapply(chunks,
                   function(k) as.integer(k[["boot"]][["n_failed"]]),
                   integer(1))
  mins   <- vapply(chunks,
                   function(k) as.numeric(k[["elapsed_mins"]]),
                   numeric(1))

  out$boot$summary    <- summ
  out$boot$n_success  <- sum(n_ok)
  out$boot$n_failed   <- sum(n_bad)
  # NA, not 0, when there is nothing to take an SD of. Zero is a CLAIM -- "the
  # base parameter did not vary" -- and one replicate cannot support it. This
  # matches boot_summary(), which also yields NA for an undefined statistic.
  out$free_sd <- if (length(free_est) > 1L) {
    stats::sd(free_est)
  } else {
    NA_real_
  }
  out$elapsed_mins <- sum(mins)
  # Character, so a provenance table prints every seed rather than silently
  # showing the first chunk's.
  out$seed  <- paste(format(seeds, scientific = FALSE), collapse = ", ")
  # The same seeds as a vector. The joined string stops being readable past a
  # handful of chunks -- at 25 it is a single 270-character table cell -- so a
  # report needs to summarise it and show the full list separately. Keeping
  # both means no consumer has to parse the string back apart.
  out$seeds    <- seeds
  out$n_chunks <- length(chunks)
  out
}

#' Find the chunk files of a chunked bootstrap run
#'
#' Returned in a deterministic order, and named so a single full run
#' (`bagging.rds`) and a chunked run never collide.
#'
#' @param out_dir Directory to look in.
#' @param prefix File-name prefix the runner used.
#'
#' @return A sorted character vector of full paths, possibly empty.
#'
#' @seealso [boot_pool_chunks()]
#'
#' @export
boot_chunk_files <- function(out_dir, prefix = "bagging") {
  # `prefix` is documented as a LITERAL file-name prefix, so it is quoted with
  # \Q...\E before becoming part of a pattern. Interpolated raw, a prefix
  # containing `.` or `+` matches files it was never meant to -- and the result
  # is a pool built from the wrong chunks, which no downstream check can see.
  pattern <- paste0("^\\Q", prefix, "\\E[.]chunk[0-9]+[.]rds$")
  files <- list.files(out_dir, full.names = TRUE)
  sort(files[grepl(pattern, basename(files), perl = TRUE)])
}

#' Is a pooled screen the run that was launched?
#'
#' @description
#' Chunks land over hours, and pooling whatever is on disk mid-run is a
#' reasonable thing to want. The hazard is that **a partial pool produces a
#' report that is wrong in no visible way**: every health check passes, every
#' frequency is honestly computed, and only the denominator is not the intended
#' one.
#'
#' @details
#' The expected totals are the only thing that can catch it, and they must come
#' from **outside** the chunks — nothing in a chunk knows how many siblings it
#' was launched alongside.
#'
#' Replicates are checked as well as chunks, because a chunk that ran short is
#' not a missing chunk and counting chunks alone would call that complete. An
#' **over**-count is reported too: it means either the expectation is stale or a
#' stray chunk from another run is being pooled, and both are worth saying.
#'
#' @param bag A pooled object from [boot_pool_chunks()], or a single run.
#' @param expect_chunks How many chunks were launched.
#' @param expect_boot How many replicates were wanted in total.
#'
#' @return `NULL` when the pool is the run that was launched; otherwise a
#'   sentence saying how it falls short, suitable for a callout.
#'
#' @seealso [boot_pool_chunks()]
#'
#' @export
boot_shortfall <- function(bag, expect_chunks, expect_boot) {
  found_chunks <- if (is.null(bag[["n_chunks"]])) {
    1L
  } else {
    as.integer(bag[["n_chunks"]])
  }
  found_boot   <- as.integer(bag[["n_boot"]])

  parts <- character(0)
  if (!identical(found_chunks, as.integer(expect_chunks))) {
    parts <- c(parts, paste0(found_chunks, " of ", expect_chunks, " chunks"))
  }
  if (!identical(found_boot, as.integer(expect_boot))) {
    parts <- c(parts, paste0(found_boot, " of ", expect_boot, " replicates"))
  }
  if (!length(parts)) return(NULL)

  paste0("This screen pooled ", paste(parts, collapse = " and "),
         ". The frequencies below are provisional: they are computed over the ",
         "replicates present, not over the run that was launched. Re-render ",
         "once the remaining chunks land.")
}
