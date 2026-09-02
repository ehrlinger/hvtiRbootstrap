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

test_that("boot_validate reads `base_params` by exact name, not by prefix", {
  # The severe member of the class. `.chk_any()` asks only whether there is a
  # value, and `$` hands it the sibling's -- so a bag MISSING a required field
  # validated clean. `base_params` is what boot_frequencies() subtracts to get
  # candidates and what boot_health() takes the free parameter from, so the
  # sibling then substitutes silently into both.
  bag <- fx_bag()
  bag$base_params <- NULL
  bag$base_params_original <- "base"
  expect_error(boot_validate(bag), "base_params")
})

test_that("boot_validate reads `manifest` by exact name, not by prefix", {
  bag <- fx_bag()
  bag$manifest <- NULL
  bag$manifest_path <- "/data/screen/manifest.json"
  expect_error(boot_validate(bag), "manifest: expected a value, found nothing")
})

test_that("boot_validate reads `boot` by exact name, not by prefix", {
  bag <- fx_bag()
  bag$boot <- NULL
  bag$boot_dir <- "/data/screen/chunks"
  expect_error(boot_validate(bag),
               "boot: expected the results list, found nothing")
})

test_that("a summary keyed variable rather than parameter is refused", {
  # This is the defect that shipped: boot_bag() filled the slot with
  # boot_summary() unrenamed. Nothing in the package reads $boot$summary, so
  # only a check here can catch the two constructors drifting apart again.
  bag <- fx_bag()
  names(bag$boot$summary)[names(bag$boot$summary) == "parameter"] <- "variable"

  expect_error(boot_validate(bag), "boot\\$summary")
})

test_that("a summary missing a count column is refused", {
  bag <- fx_bag()
  bag$boot$summary$n <- NULL

  expect_error(boot_validate(bag), "boot\\$summary")
})

test_that("an unnamed summary names the class found, not trailing off", {
  # names(s) is NULL for an unnamed vector, and pasting that collapses to
  # "", so the message used to read "found " with nothing after it. It
  # must say something concrete instead.
  bag <- fx_bag()
  bag$boot$summary <- c(1, 2, 3)

  err <- expect_error(boot_validate(bag), "boot\\$summary")
  expect_match(conditionMessage(err), "found an unnamed numeric",
               fixed = TRUE)
})

test_that("the three columns a report reads are enough", {
  # Deliberately NOT the nine columns .bag_summary() produces. boot_validate()
  # accepts bags written by runners, and the fixture and this function's own
  # documented example both carry exactly parameter/n/pct. The nine-column
  # agreement between boot_bag() and boot_pool_chunks() is guaranteed by their
  # sharing .bag_summary(), which is stronger than a check here.
  expect_true(boot_validate(fx_bag()))
})
