test_that("boot_health returns a check per row with a pass/fail column", {
  out <- boot_health(fx_bag())
  expect_s3_class(out, "data.frame")
  expect_named(out, c("check", "value", "ok", "note"))
  expect_type(out$ok, "logical")
  expect_type(out$value, "character")
})

test_that("a healthy screen fails nothing", {
  out <- boot_health(fx_bag())
  expect_false(any(out$ok %in% FALSE))
})

test_that("a screen that selected nothing is a FAILURE, not an empty table", {
  # The signature of a formula that did not survive the per-replicate
  # rewrite: the refit errors, the error is caught, the step reports nothing
  # accepted, and the screen halts having selected nothing -- with no warning
  # and n_failed = 0. The summary then reads as a table of perfectly reliable
  # variables. Absence from the frequency table is not enough; it has to be
  # a row that says FALSE.
  bag <- fx_bag_counts(list(), n_boot = 10L)
  out <- boot_health(bag)
  row <- out[out$check == "Distinct candidates ever selected", ]
  expect_identical(row$value, "0")
  expect_false(row$ok)
  expect_true(any(out$ok %in% FALSE))
  expect_match(row$note, "selected")
})

test_that("a base parameter that never varied is a FAILURE", {
  # A bootstrap built on the vector interface returns the original fit every
  # replicate, with n_success = 500, n_failed = 0 and no warning. sd() of a
  # free base parameter is the only tell.
  bag <- fx_bag()
  bag$free_sd <- 0
  out <- boot_health(bag)
  row <- out[out$check == "SD of the first free base parameter", ]
  expect_false(row$ok)
  expect_match(row$note, "same fit")
})

test_that("free_sd is recomputed when the bag does not carry it", {
  # boot_pool_chunks() computes free_sd, so a SINGLE unchunked run does not
  # have it -- and an unchunked run is the shape most likely to have been
  # built the way this check exists to catch. Skipping it there would turn
  # the check off in exactly the case that needs it.
  bag <- fx_bag()
  bag$free_sd <- NULL
  out <- boot_health(bag)
  row <- out[out$check == "SD of the first free base parameter", ]
  expect_identical(row$value, format(stats::sd(c(1.0, 1.1, 0.9, 1.2))))
  expect_true(is.na(row$ok) || row$ok)
})

test_that("one replicate gives NA, never 0, and is not called a failure", {
  # Zero is the CLAIM that the parameter did not vary, and one replicate
  # cannot support it.
  bag <- fx_bag_counts(list(), n_boot = 1L)
  bag$free_sd <- NULL
  out <- boot_health(bag)
  row <- out[out$check == "SD of the first free base parameter", ]
  expect_identical(row$value, "NA")
  expect_false(isFALSE(row$ok))
})

test_that("boot_health reports the fitted and failed counts", {
  bag <- fx_bag()
  bag$boot$n_success <- 497L
  bag$boot$n_failed <- 3L
  out <- boot_health(bag)
  expect_identical(out$value[out$check == "Replicates that fitted"], "497")
  expect_identical(out$value[out$check == "Replicates that failed"], "3")
})

test_that("a screen where nothing fitted is a failure", {
  bag <- fx_bag()
  bag$boot$n_success <- 0L
  out <- boot_health(bag)
  expect_false(out$ok[out$check == "Replicates that fitted"])
})

test_that("boot_health returns rather than stopping", {
  # The template decides how to present a failure -- a callout, a stop(), a
  # red cell. This function's job is to say what is wrong, not what to do.
  bag <- fx_bag_counts(list(), n_boot = 10L)
  expect_no_error(boot_health(bag))
})

test_that("boot_health calls boot_validate and propagates its error", {
  bag <- fx_bag()
  bag$base_params <- NULL
  expect_error(boot_health(bag), "base_params")
})

test_that("boot_health reads `free_sd` by exact name, not by prefix", {
  bag <- fx_bag()
  bag$free_sd <- NULL
  bag$free_sd_by_phase <- c(early = 0, late = 0.7)
  out <- boot_health(bag)
  row <- out[out$check == "SD of the first free base parameter", ]
  expect_identical(row$value, format(stats::sd(c(1.0, 1.1, 0.9, 1.2))))
  expect_true(row$ok)
})
