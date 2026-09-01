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

test_that("boot_validate requires the manifest to be a list", {
  # It is indexed by name, and `manifest[["sha256"]]` on a named ATOMIC
  # vector that lacks the name is not NULL -- it is "subscript out of
  # bounds", an error naming neither the field nor the file. The same
  # indexing happens in boot_pool_chunks().
  bag <- fx_bag()
  bag$manifest <- c(md5sum = "abc")
  err <- expect_error(boot_validate(bag), "manifest")
  expect_match(conditionMessage(err), "found character")
})

test_that("boot_validate accepts a manifest with neither digest", {
  # Which digests a runner records is its business; that the manifest is a
  # list is not. boot_provenance() reports NA for a checksum it cannot find,
  # and that is a legitimate screen, not a malformed one.
  bag <- fx_bag()
  bag$manifest <- list(md5sum = "abc")
  expect_true(boot_validate(bag))
  expect_true(is.na(
    boot_provenance(bag)$value[boot_provenance(bag)$item == "Dataset checksum"]
  ))
})

test_that("a per-phase free_sd is refused, naming the field", {
  # `free_sd` is the SD of the FIRST free base parameter, and
  # boot_pool_chunks() -- its only writer -- computes one number. A runner
  # extending the per-phase reasoning of `requested` to it produced a bag
  # that validated and then killed boot_health() with a message naming
  # neither the field nor the function.
  bag <- fx_bag()
  bag$free_sd <- c(early = 0.5, late = 0.7)
  expect_error(boot_validate(bag), "free_sd")
})

test_that("an absent free_sd is still valid", {
  # Optional: a single unchunked run never went through boot_pool_chunks()
  # and carries none. Refusing the per-phase shape must not require the
  # scalar one.
  bag <- fx_bag()
  bag$free_sd <- NULL
  expect_true(boot_validate(bag))
})
