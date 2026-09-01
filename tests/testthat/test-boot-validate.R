test_that("boot_validate accepts a well-formed bag", {
  bag <- fx_bag()
  expect_true(boot_validate(bag))
})

test_that("boot_validate names every missing field at once", {
  # One render per missing field turns a single fix into five renders, so the
  # message has to carry the whole list.
  bag <- fx_bag()
  bag$seed <- NULL
  bag$n_rows <- NULL
  err <- expect_error(boot_validate(bag))
  expect_match(conditionMessage(err), "seed")
  expect_match(conditionMessage(err), "n_rows")
})

test_that("boot_validate rejects a scalar field that is not scalar", {
  # The defect this function exists to catch. `n_boot` is one number; a
  # length-2 value means the pool was written per phase into a field that
  # is not per phase, and every count downstream is then ambiguous.
  bag <- fx_bag()
  bag$n_boot <- c(500L, 500L)
  expect_error(boot_validate(bag), "n_boot")
})

test_that("boot_validate accepts a per-phase field being per phase", {
  # `requested` and `usable` ARE per phase on a multiphase screen. This is
  # the case that must NOT error -- it is valid, and the template's job is
  # to render it, not to reject it.
  bag <- fx_bag()
  bag$requested <- c(early = 230L, late = 230L)
  bag$usable <- c(early = 226L, late = 226L)
  expect_true(boot_validate(bag))
})

test_that("boot_validate rejects a zero-length field", {
  # character(0) satisfies "is present" and destroys any table built from
  # it, because it contributes no element rather than one.
  bag <- fx_bag()
  bag$n_rows <- integer(0)
  expect_error(boot_validate(bag), "n_rows")
})

test_that("boot_validate rejects a zero-length per-phase field", {
  # Same failure, on the side of the contract that tolerates a vector: at
  # least one value is still required, or the row vanishes.
  bag <- fx_bag()
  bag$usable <- integer(0)
  expect_error(boot_validate(bag), "usable")
})

test_that("boot_validate rejects a non-numeric per-phase field", {
  bag <- fx_bag()
  bag$requested <- "many"
  expect_error(boot_validate(bag), "requested")
})

test_that("boot_validate rejects an NA in a required scalar", {
  bag <- fx_bag()
  bag$slentry <- NA_real_
  expect_error(boot_validate(bag), "slentry")
})

test_that("boot_validate checks the nested boot fields", {
  bag <- fx_bag()
  bag$boot$n_success <- NULL
  expect_error(boot_validate(bag), "boot\\$n_success")
})

test_that("boot_validate reports an absent boot list without indexing it", {
  # `boot` missing entirely must name `boot`, not four nested fields it
  # could not have looked at.
  bag <- fx_bag()
  bag$boot <- NULL
  err <- expect_error(boot_validate(bag))
  expect_match(conditionMessage(err), "boot")
  expect_false(grepl("boot\\$replicates", conditionMessage(err)))
})

test_that("boot_validate says what it expected and what it found", {
  # The error a study author sees is the only documentation they will read.
  bag <- fx_bag()
  bag$n_boot <- c(500L, 500L)
  expect_error(boot_validate(bag), "found length 2")
})

test_that("boot_validate rejects something that is not a bag at all", {
  expect_error(boot_validate("bagging.rds"), "list")
})
