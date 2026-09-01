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
    max_steps = 50L, elapsed_mins = 1, manifest = list(md5 = "abc"),
    th_version = "1.2.6",
    boot = list(replicates = reps, n_success = n_boot, n_failed = 0L)
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
  expect_error(boot_pool_chunks(list(bad, chunk(2))), "no boot\\$replicates")
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

# boot_pool_chunks() calls no validator, so every field it reads from a chunk
# is in the reachable class: there is nothing in front of it to turn an absent
# field into an error first. These two tests cover that whole surface.

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
    expect_error(boot_pool_chunks(list(sib(1), sib(2))), "no chunk records",
                 info = f)
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
