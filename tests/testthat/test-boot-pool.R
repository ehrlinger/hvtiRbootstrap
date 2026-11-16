# A chunk carrying every field boot_pool_chunks() gates on.
chunk <- function(seed, n_boot = 2L, reps = NULL, ...) {
  if (is.null(reps)) {
    reps <- data.frame(
      replicate = rep(seq_len(n_boot), each = 2L),
      parameter = rep(c("early.age", "late.bsa"), times = n_boot),
      estimate = seq_len(2L * n_boot) / 10,
      stringsAsFactors = FALSE
    )
  }
  modifyList(list(
    seed = seed, n_boot = n_boot, slentry = 0.1, slstay = 0.07,
    base_params = "early.log_mu", usable = c(early = 10L, late = 10L),
    requested = c(early = 10L, late = 10L), n_rows = 500L,
    max_steps = 50L, elapsed_mins = 1, manifest = list(md5 = "abc"),
    th_version = "1.2.6",
    boot = list(replicates = reps,
                summary = data.frame(parameter = "early.age", n = 1L,
                                     pct = 50),
                n_success = n_boot, n_failed = 0L)
  ), list(...))
}

test_that("pooling stacks replicates and re-indexes them", {
  # Replicate ids run 1..n_boot INSIDE each chunk, so they collide across
  # chunks. Without the offset, replicate 1 of chunk 2 merges into replicate 1
  # of chunk 1 and a variable selected in both counts once instead of twice --
  # understating every frequency, in a table that looks entirely ordinary.
  p <- boot_pool_chunks(list(chunk(1), chunk(2)))
  expect_equal(p$n_boot, 4L)
  expect_equal(p$n_chunks, 2L)
  expect_equal(sort(unique(p$boot$replicates$replicate)), 1:4)
})

test_that("a shared seed is refused", {
  # Same seed means the SAME replicates: pooling counts each twice and reports
  # a Monte-Carlo error smaller than the run actually has.
  expect_error(boot_pool_chunks(list(chunk(7), chunk(7))), "share the seed")
})

test_that("chunks that disagree on a gated field are refused", {
  expect_error(boot_pool_chunks(list(chunk(1), chunk(2, max_steps = 10L))),
               "step cap")
  expect_error(boot_pool_chunks(list(chunk(1), chunk(2, slentry = 0.3))),
               "slentry")
  other_md5 <- chunk(2, manifest = list(md5 = "zzz"))
  expect_error(boot_pool_chunks(list(chunk(1), other_md5)),
               "dataset checksum")
})

test_that("a field NO chunk records is refused, not passed unanimously", {
  # The whole point of checking absence BEFORE agreement. A field nobody
  # records formats identically everywhere, so it passes unanimously and the
  # accessor hands back NULL as the agreed value. A gate that cannot tell
  # "everyone agrees" from "nobody recorded it" is worse than no gate, because
  # it reads as a check that happened. This was real: max_steps was absent from
  # every chunk in a fixture and the suite was green.
  bare <- function(s) {
    k <- chunk(s)
    k$max_steps <- NULL
    k
  }
  expect_error(boot_pool_chunks(list(bare(1), bare(2))), "no chunk records")
})

test_that("a field only SOME chunks record is refused", {
  k <- chunk(2)
  k$max_steps <- NULL
  expect_error(boot_pool_chunks(list(chunk(1), k)), "cannot be compared")
})

test_that("chunks that resampled differently are refused", {
  # Patients and rows are different resampling distributions on start/stop
  # data, so their replicates are not draws from one screen.
  expect_error(
    boot_pool_chunks(list(chunk(1, resampled = "patients"),
                          chunk(2, resampled = "rows"))),
    "resampled"
  )
})

test_that("an absent `resampled` reads as rows, so legacy chunks pool", {
  # Every runner before hvtiRtemplates#443 resampled rows and recorded nothing.
  p <- boot_pool_chunks(list(chunk(1), chunk(2)))
  expect_identical(p$resampled, "rows")
  p <- boot_pool_chunks(list(chunk(1), chunk(2, resampled = "rows")))
  expect_identical(p$resampled, "rows")
  # Legacy first, so the value cannot simply be chunk 1's.
  expect_error(
    boot_pool_chunks(list(chunk(1), chunk(2, resampled = "patients"))),
    "resampled"
  )
})

test_that("the pooled bag carries an agreed `resampled = \"patients\"`", {
  p <- boot_pool_chunks(list(chunk(1, resampled = "patients"),
                             chunk(2, resampled = "patients")))
  expect_identical(p$resampled, "patients")
})

test_that("the checksum algorithm travels with the digest", {
  # An md5 and a sha256 of the same file are different strings. Comparing bare
  # digests across algorithms compares things that are not comparable.
  a <- chunk(1, manifest = list(md5 = "abc"))
  b <- chunk(2, manifest = list(sha256 = "abc"))
  expect_error(boot_pool_chunks(list(a, b)), "dataset checksum")
})

test_that("a chunk naming its commit is not pooled with one that cannot", {
  a <- chunk(1)                                   # th_version only
  b <- chunk(2, th_sha = "deadbee")
  expect_error(boot_pool_chunks(list(a, b)), "fitting engine version")
})

test_that("the pooled summary is recomputed, not averaged", {
  # A percentage of a percentage is not a percentage of the whole, and the
  # chunks need not be the same size.
  p <- boot_pool_chunks(list(chunk(1, n_boot = 2L), chunk(2, n_boot = 2L)))
  s <- p$boot$summary
  expect_equal(s$pct[s$parameter == "early.age"], 100)
  expect_equal(sum(s$n[s$parameter == "early.age"]), 4L)
})

test_that("the pooled summary has the same shape as the bagged one", {
  # These two built $boot$summary separately: seven columns keyed `variable`
  # from boot_bag(), nine keyed `parameter` here. A renderer saw the quantile
  # columns only if the run happened to be chunked.
  set.seed(1)
  n <- 200
  x1 <- rnorm(n)
  df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1, x2 = rnorm(n))
  fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_rep = 20, seed = 42)
  bagged <- boot_bag(fit, base_params = "(Intercept)", requested = 2L,
                     manifest = list(sha256 = "abc123"))

  pooled <- boot_pool_chunks(list(chunk(1), chunk(2)))

  expect_equal(names(pooled$boot$summary), names(bagged$boot$summary))
})

test_that("pooled summary drops false confidence intervals", {
  # ci_lower/ci_upper were computed over the NA-dropped replicates, so they
  # were conditional on selection and were not confidence intervals at all.
  p <- boot_pool_chunks(list(chunk(1), chunk(2)))

  expect_false("ci_lower" %in% names(p$boot$summary))
  expect_false("ci_upper" %in% names(p$boot$summary))
  expect_true(all(c("sel_q025", "sel_q975") %in% names(p$boot$summary)))
})

test_that("pooling nothing is an error", {
  expect_error(boot_pool_chunks(list()), "no chunks to pool")
})

test_that("boot_chunk_files finds chunks and ignores a single full run", {
  d <- withr::local_tempdir()
  for (f in c("bagging.chunk01.rds", "bagging.chunk02.rds", "bagging.rds",
              "other.chunk01.rds")) {
    saveRDS(1, file.path(d, f))
  }
  got <- basename(boot_chunk_files(d))
  expect_equal(got, c("bagging.chunk01.rds", "bagging.chunk02.rds"))
})

test_that("boot_shortfall is NULL only when the pool is the launched run", {
  p <- boot_pool_chunks(list(chunk(1), chunk(2)))
  expect_null(boot_shortfall(p, expect_chunks = 2L, expect_boot = 4L))
  expect_match(boot_shortfall(p, 3L, 6L), "2 of 3 chunks and 4 of 6 replicates")
  # A chunk that ran SHORT is not a missing chunk: counting chunks alone would
  # call that complete.
  expect_match(boot_shortfall(p, 2L, 6L), "4 of 6 replicates")
  # An over-count is reported too -- a stale expectation, or a stray chunk from
  # another run being pooled.
  expect_match(boot_shortfall(p, 1L, 4L), "2 of 1 chunks")
})

test_that("boot_shortfall treats an unchunked run as one chunk", {
  expect_null(boot_shortfall(list(n_boot = 500L), 1L, 500L))
})

test_that("a replicate id outside 1..n_boot is refused", {
  # The offset arithmetic is only sound if the ids stay in range. Out of range
  # does not error on its own -- the id lands on top of a neighbouring chunk's
  # replicate, and the only symptom is a frequency slightly too low.
  bad <- chunk(1)
  bad$boot$replicates$replicate <- bad$boot$replicates$replicate + 5L
  expect_error(boot_pool_chunks(list(bad, chunk(2))), "replicate ids run")
})

test_that("a chunk without a usable replicates frame is refused", {
  bad <- chunk(1)
  bad$boot$replicates <- NULL
  # Absent altogether, boot_validate() refuses it before the pool looks.
  expect_error(boot_pool_chunks(list(bad, chunk(2))), "boot\\$replicates")
  bad2 <- chunk(1)
  bad2$boot$replicates$estimate <- NULL
  expect_error(boot_pool_chunks(list(bad2, chunk(2))), "no boot\\$replicates")
})

test_that("free_sd is NA, not 0, when there is nothing to take an SD of", {
  # Zero is a CLAIM -- "the base parameter did not vary" -- and one replicate
  # cannot support it.
  one <- chunk(1, n_boot = 1L)
  one$boot$replicates <- data.frame(
    replicate = 1L,
    parameter = "early.log_mu",
    estimate = 0.5,
    stringsAsFactors = FALSE
  )
  p <- boot_pool_chunks(list(one))
  expect_true(is.na(p$free_sd))
})

test_that("a disagreement message is readable, with no control characters", {
  a <- chunk(1, usable = c(early = 10L, late = 10L))
  b <- chunk(2, usable = c(early = 11L, late = 10L))
  msg <- tryCatch(boot_pool_chunks(list(a, b)), error = conditionMessage)
  expect_false(grepl("\r", msg, fixed = TRUE))
  expect_match(msg, "usable candidate counts")
})

test_that("boot_chunk_files treats prefix as a literal, not a pattern", {
  # Unescaped, a `.` in the prefix matches any character and the pool is built
  # from the wrong chunks -- which no downstream check can see.
  d <- withr::local_tempdir()
  for (f in c("a.b.chunk01.rds", "axb.chunk01.rds")) saveRDS(1, file.path(d, f))
  expect_equal(basename(boot_chunk_files(d, prefix = "a.b")), "a.b.chunk01.rds")
})

test_that("boot_shortfall reads `n_chunks` by exact name, not by prefix", {
  bag <- fx_bag()
  bag$n_chunks <- NULL
  bag$n_chunks_expected <- 25L
  expect_null(boot_shortfall(bag, expect_chunks = 1L, expect_boot = 4L))
})

# boot_pool_chunks() validates every chunk first, so some absent fields are
# now refused by boot_validate() rather than by a gate. Either refusal will
# do: what these tests pin is that a sibling field is never read in place of
# the real one.

test_that("every gated chunk field is read by exact name, not by prefix", {
  # The gates exist to refuse chunks that are not draws from the same screen.
  # Read by prefix, a gate compares SIBLINGS -- and when the chunks agree on
  # the sibling, it passes on evidence it never had, which is the one outcome
  # the "no chunk records" branch was written to prevent.
  gated <- c(slentry = "slentry_used", slstay = "slstay_used",
             base_params = "base_params_original", usable = "usable_counts",
             max_steps = "max_steps_used", manifest = "manifest_path")
  for (f in names(gated)) {
    sib <- function(s) {
      k <- chunk(s)
      k[[f]] <- NULL
      k[[gated[[f]]]] <- "X"
      k
    }
    expect_error(boot_pool_chunks(list(sib(1), sib(2))),
                 "no chunk records|not a valid bag", info = f)
  }
})

test_that("the engine-provenance gate reads `th_sha` by exact name", {
  # Two fields with a fallback between them, so it needs its own case: a
  # chunk recording `th_sha256` and no `th_sha` made the gate return
  # "sha:<a digest of something else>" and call the engine verified.
  sib <- function(s) {
    k <- chunk(s)
    k$th_version <- NULL
    k$th_sha256 <- "aaa111"
    k
  }
  expect_error(boot_pool_chunks(list(sib(1), sib(2))), "no chunk records")
})

test_that("an ungated chunk field is not silently taken from a sibling", {
  # These are read straight, with no gate to fail first, so an absent field
  # taken from a sibling pools a WRONG NUMBER rather than refusing. Read
  # exactly, the absent field fails instead -- which is the whole ask.
  ungated <- c(seed = "seeds", n_boot = "n_boot_requested",
               elapsed_mins = "elapsed_mins_total")
  for (f in names(ungated)) {
    sib <- function(s) {
      k <- chunk(s)
      k[[f]] <- NULL
      k[[ungated[[f]]]] <- if (f == "seed") s else 99
      k
    }
    expect_error(boot_pool_chunks(list(sib(1), sib(2))), info = f)
  }
})

# The real path, end to end: boot_select() -> boot_bag() -> boot_pool_chunks().
# Every pool test above hand-builds its chunks in the hazard runner's shape,
# which is how boot_pool_chunks() came to refuse this package's own bags:
# boot_bag() wrote `engine` and no `max_steps`, and the pool gates on both.
real_bag <- function(seed, ...) {
  set.seed(5)
  n  <- 120
  x1 <- stats::rnorm(n)
  df <- data.frame(y = 2 * x1 + stats::rnorm(n), x1 = x1,
                   x2 = stats::rnorm(n))
  fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_rep = 8, seed = seed,
                     ...)
  boot_bag(fit, base_params = "(Intercept)", requested = 2L,
           manifest = list(sha256 = "same-data"))
}

test_that("two boot_bag() runs pool through boot_pool_chunks()", {
  a <- real_bag(1)
  b <- real_bag(2)
  p <- boot_pool_chunks(list(a, b))

  expect_identical(p$n_boot, 16L)
  expect_identical(p$n_chunks, 2L)
  expect_identical(p$seeds, c(1, 2))
  expect_identical(p$resampled, "rows")
  expect_silent(boot_validate(p))
  # Recomputed from the pooled replicates, not averaged.
  x1 <- p$boot$summary[p$boot$summary$parameter == "x1", ]
  n_x1 <- sum(a$boot$replicates$parameter == "x1") +
    sum(b$boot$replicates$parameter == "x1")
  expect_identical(as.integer(x1$n), as.integer(n_x1))
})

test_that("bags from different screens refuse to pool", {
  expect_error(boot_pool_chunks(list(real_bag(1), real_bag(2, max_steps = 3))),
               "step cap")
  expect_error(boot_pool_chunks(list(real_bag(1),
                                     real_bag(2, select = "none"))),
               "selection method|slentry")
  expect_error(boot_pool_chunks(list(real_bag(1), real_bag(2, fraction = 0.5))),
               "draw fraction")
})

test_that("a recorded engine commit gates; an NA one falls back to version", {
  a <- real_bag(1)
  b <- real_bag(2)
  a$engine_sha <- "aaa"
  b$engine_sha <- "bbb"
  expect_error(boot_pool_chunks(list(a, b)), "fitting engine")
  # A sha against no sha is two kinds of evidence, and is refused too.
  b$engine_sha <- NA_character_
  expect_error(boot_pool_chunks(list(a, b)), "fitting engine")
  a$engine_sha <- NA_character_
  expect_identical(boot_pool_chunks(list(a, b))$n_chunks, 2L)
})

test_that("a chunk missing a field is named, not a raw vapply() error", {
  bad <- chunk(1)
  bad$boot$n_success <- NULL
  expect_error(boot_pool_chunks(list(chunk(2), bad)),
               "chunk 2 is not a valid bag.*boot\\$n_success")
})

test_that("a runner chunk without method or fraction still pools", {
  # The hazard runner records neither. Read as "stepwise" and 1, as
  # `resampled` is read as "rows".
  expect_identical(boot_pool_chunks(list(chunk(1), chunk(2)))$n_chunks, 2L)
  expect_error(boot_pool_chunks(list(chunk(1), chunk(2, method = "none"))),
               "selection method")
})

test_that("bags from different models refuse to pool (#71 review)", {
  # Same data, same candidate COUNT, same seed-free gates: before the model
  # was recorded, a linear and a logistic screen pooled, averaging slopes
  # with log-odds, and two formulas offering one candidate each pooled too.
  set.seed(1)
  d <- data.frame(x = stats::rnorm(100), z = stats::rnorm(100))
  d$y <- as.integer(d$x + stats::rnorm(100) > 0)
  bag <- function(formula, fitter, seed) {
    boot_bag(boot_select(d, formula, fitter, n_rep = 5, seed = seed),
             base_params = "(Intercept)", requested = 1L,
             manifest = list(sha256 = "same"))
  }
  expect_error(
    boot_pool_chunks(list(bag(y ~ x, fit_linear, 1),
                          bag(y ~ x, fit_logistic, 2))),
    "the fitter"
  )
  expect_error(
    boot_pool_chunks(list(bag(y ~ x, fit_linear, 1),
                          bag(y ~ z, fit_linear, 2))),
    "model formula"
  )
  # A custom fitter is fingerprinted, so two different ones disagree...
  f1 <- function(data, formula, select) fit_linear(data, formula, select)
  f2 <- function(data, formula, select) {
    fit_linear(data, formula, list(method = "none"))
  }
  expect_error(
    boot_pool_chunks(list(bag(y ~ x, f1, 1), bag(y ~ x, f2, 2))),
    "the fitter"
  )
  # ...and the same one agrees with itself.
  expect_identical(
    boot_pool_chunks(list(bag(y ~ x, f1, 1), bag(y ~ x, f1, 2)))$n_chunks,
    2L
  )
})

test_that("a non-runner chunk that records no model is refused", {
  a <- real_bag(1)
  b <- real_bag(2)
  a$fitter <- NULL
  b$fitter <- NULL
  expect_error(boot_pool_chunks(list(a, b)), "no chunk records the fitter")
})
