test_that("boot_provenance returns one row per fact", {
  bag <- fx_bag()
  out <- boot_provenance(bag)
  expect_s3_class(out, "data.frame")
  expect_named(out, c("item", "value"))
  expect_type(out$value, "character")
  expect_gt(nrow(out), 0L)
})

test_that("boot_provenance calls boot_validate and propagates its error", {
  bag <- fx_bag()
  bag$n_boot <- c(500L, 500L)
  expect_error(boot_provenance(bag), "n_boot")
})

# The four shapes. `requested` and `usable` are per phase on a multiphase
# screen, and the row count must not depend on which shape arrived -- that is
# the assertion that would have caught the original defect, where a length-2
# value against a length-13 item column made data.frame() error outright.
test_that("boot_provenance returns the same rows for every shape", {
  n_scalar <- nrow(boot_provenance(fx_bag()))

  bag <- fx_bag()
  bag$requested <- c(early = 230L, late = 230L)
  bag$usable <- c(early = 226L, late = 226L)
  expect_identical(nrow(boot_provenance(bag)), n_scalar)

  bag <- fx_bag()
  bag$requested <- c(230L, 230L)
  bag$usable <- c(226L, 226L)
  expect_identical(nrow(boot_provenance(bag)), n_scalar)
})

test_that("a named per-phase value is labelled, not summed", {
  # The pool is OFFERED to each phase, so 230 and 230 is one pool seen twice
  # rather than 460 candidates. Summing them would report a screen that never
  # happened.
  bag <- fx_bag()
  bag$requested <- c(early = 230L, late = 230L)
  out <- boot_provenance(bag)
  offered <- out$value[out$item == "Candidates offered"]
  expect_identical(offered, "early 230, late 230")
  expect_false(grepl("460", offered, fixed = TRUE))
})

test_that("an unnamed per-phase value is comma-joined", {
  bag <- fx_bag()
  bag$requested <- c(230L, 240L)
  out <- boot_provenance(bag)
  expect_identical(out$value[out$item == "Candidates offered"], "230, 240")
})

test_that(".per_phase yields exactly one string for a zero-length value", {
  # boot_validate() now rejects a zero-length `requested` upstream, so this is
  # the second line of defence rather than a reachable path through
  # boot_provenance(). Tested directly because the failure it prevents is
  # silent: format(integer(0)) is character(0), which contributes no element
  # rather than one, and the row simply vanishes.
  expect_identical(.per_phase(integer(0)), NA_character_)
  expect_length(.per_phase(integer(0)), 1L)
  expect_identical(.per_phase(230L), "230")
})

test_that("the checksum carries its algorithm, sha256 before md5", {
  # An md5 and a sha256 of the same file are different strings, and of
  # different files may not be, so a bare digest is not evidence of anything.
  bag <- fx_bag()
  bag$manifest <- list(md5 = "aaa", sha256 = "bbb")
  out <- boot_provenance(bag)
  expect_identical(out$value[out$item == "Dataset checksum"], "sha256:bbb")

  bag$manifest <- list(md5 = "aaa")
  out <- boot_provenance(bag)
  expect_identical(out$value[out$item == "Dataset checksum"], "md5:aaa")
})

test_that("the fitting engine prefers a commit to a version string", {
  # One real package version existed as two codebases, one with a selection
  # criterion and one without, and the selection criterion is precisely what
  # decides what a screen selects.
  bag <- fx_bag()
  bag$th_version <- "1.2.0"
  expect_identical(
    boot_provenance(bag)$value[boot_provenance(bag)$item == "Fitting engine"],
    "sha:deadbeef"
  )

  bag$th_sha <- NULL
  out <- boot_provenance(bag)
  expect_identical(out$value[out$item == "Fitting engine"], "version:1.2.0")

  bag$th_version <- NULL
  out <- boot_provenance(bag)
  expect_true(is.na(out$value[out$item == "Fitting engine"]))
})

test_that("elapsed time is reported as summed CPU hours", {
  # boot_pool_chunks() SUMS elapsed across chunks, so this is total compute,
  # not wall clock: chunks run in parallel finish in a fraction of it.
  bag <- fx_bag()
  bag$elapsed_mins <- 150
  out <- boot_provenance(bag)
  expect_identical(out$value[out$item == "CPU hours (summed)"], "2.5")
})

test_that("an unchunked run reports one chunk", {
  bag <- fx_bag()
  bag$n_chunks <- NULL
  out <- boot_provenance(bag)
  expect_identical(out$value[out$item == "Chunks pooled"], "1")
})

test_that("boot_seeds lists every seed of a pooled run", {
  bag <- fx_bag()
  out <- boot_seeds(bag)
  expect_named(out, c("chunk", "seed"))
  expect_identical(nrow(out), 2L)
  expect_identical(out$seed, c("101", "202"))
})

test_that("boot_seeds falls back to the scalar seed of a single run", {
  # A single unchunked run never went through boot_pool_chunks() and carries
  # only the scalar `seed` its runner wrote. Without the fallback, the one
  # case this table exists to serve is the one case it cannot render.
  bag <- fx_bag()
  bag$seeds <- NULL
  bag$seed <- 4242
  out <- boot_seeds(bag)
  expect_identical(nrow(out), 1L)
  expect_identical(out$seed, "4242")
})

test_that("boot_seeds does not render a large seed in scientific notation", {
  # A seed printed as 1.23e+08 cannot be typed back in to reproduce the run.
  bag <- fx_bag()
  bag$seeds <- NULL
  bag$seed <- 123456789
  expect_identical(boot_seeds(bag)$seed, "123456789")
})

test_that("boot_seeds calls boot_validate and propagates its error", {
  bag <- fx_bag()
  bag$boot$summary <- NULL
  expect_error(boot_seeds(bag), "boot\\$summary")
})

test_that("boot_provenance reads `n_chunks` by exact name, not by prefix", {
  bag <- fx_bag()
  bag$n_chunks <- NULL
  bag$n_chunks_expected <- 25L
  out <- boot_provenance(bag)
  expect_identical(out$value[out$item == "Chunks pooled"], "1")
})

test_that("boot_provenance reads `th_sha` by exact name, not by prefix", {
  bag <- fx_bag()
  bag$th_sha <- NULL
  bag$th_sha256 <- "deadbeef"
  bag$th_version <- "1.2.3"
  out <- boot_provenance(bag)
  expect_true(any(grepl("version:1.2.3", out$value, fixed = TRUE)))
})

test_that("boot_seeds reads `seeds` by exact name, not by prefix", {
  bag <- fx_bag()
  bag$seeds <- NULL
  bag$seeds_by_chunk <- c(101, 202, 303)
  bag$seed <- 4242
  out <- boot_seeds(bag)
  expect_identical(nrow(out), 1L)
  expect_identical(out$seed, "4242")
})
