test_that("boot_frequencies returns the documented columns", {
  out <- boot_frequencies(fx_bag())
  expect_s3_class(out, "data.frame")
  expect_named(out, c("variable", "term", "n", "pct", "mc_error",
                      "near_threshold", "retained"))
})

test_that("boot_frequencies drops the base parameters", {
  # A base parameter is in every replicate by construction. Reporting it at
  # 100% invites it to be read as the most reliable finding of the screen.
  out <- boot_frequencies(fx_bag())
  expect_false("base" %in% out$term)
  expect_setequal(out$term,
                  c("early.age", "early.ln_age", "early.bmi", "late.age"))
})

test_that("boot_frequencies does not reimplement boot_summary", {
  # The one thing this package is parity-tested on is the selection count. A
  # second implementation of it here is the defect this test exists to
  # prevent, so `n` and `pct` are pinned to boot_summary() term by term.
  bag <- fx_bag()
  out <- boot_frequencies(bag)
  ref <- boot_summary(.replicate_matrix(bag))
  ref <- ref[match(out$term, ref$variable), , drop = FALSE]
  expect_identical(out$n, ref$n)
  expect_identical(out$pct, ref$pct)
})

test_that("the denominator is n_boot, not the replicates that selected", {
  # A replicate in which nothing outside the base model was selected writes
  # NO rows to the long replicate table. Counting the ids present would use
  # a smaller denominator and inflate every frequency in the report.
  bag <- fx_bag()
  bag$n_boot <- 8L
  out <- boot_frequencies(bag)
  expect_identical(out$pct[out$term == "early.age"], 25)
  expect_identical(nrow(.replicate_matrix(bag)), 8L)
})

test_that("a replicate id outside 1..n_boot is refused", {
  # boot_pool_chunks() checks this for chunks; a single unchunked run has
  # never been through it. An out-of-range id does not error on its own, it
  # lands on another replicate's row and understates a frequency.
  bag <- fx_bag()
  bag$n_boot <- 2L
  expect_error(boot_frequencies(bag), "replicate")
})

test_that("Monte-Carlo error is per variable, largest at 50%", {
  # A single quoted figure overstates the error for the variables at the top
  # and understates it in the middle -- and the middle is where the retention
  # decision is actually being made.
  bag <- fx_bag_counts(list(a = 200L, b = 40L), n_boot = 400L)
  out <- boot_frequencies(bag)
  expect_equal(out$mc_error[out$term == "a"], 2.5)
  expect_equal(out$mc_error[out$term == "b"], 100 * sqrt(0.1 * 0.9 / 400))
  expect_gt(out$mc_error[out$term == "a"], out$mc_error[out$term == "b"])
})

test_that("near_threshold marks retention that would not survive a rerun", {
  bag <- fx_bag_counts(list(a = 200L, b = 40L, c = 210L), n_boot = 400L)
  out <- boot_frequencies(bag, threshold = 50)
  expect_true(out$near_threshold[out$term == "a"])
  expect_true(out$near_threshold[out$term == "c"])
  expect_false(out$near_threshold[out$term == "b"])
})

test_that("without a threshold there is no near-threshold claim", {
  # NA, not FALSE. FALSE is the claim "this retention is stable", and with no
  # cutoff supplied there is no retention decision to be stable about.
  out <- boot_frequencies(fx_bag())
  expect_true(all(is.na(out$near_threshold)))
  expect_true(all(is.na(out$retained)))
})

test_that("retained is the cutoff applied to the frequency", {
  bag <- fx_bag_counts(list(a = 200L, b = 40L), n_boot = 400L)
  out <- boot_frequencies(bag, threshold = 50)
  expect_true(out$retained[out$term == "a"])
  expect_false(out$retained[out$term == "b"])
})

test_that("without a phase rule there is no phase dimension", {
  out <- boot_frequencies(fx_bag())
  expect_false("phase" %in% names(out))
  expect_identical(out$variable, out$term)
})

test_that("a phase rule splits the term into phase and variable", {
  # One variable offered to two phases is two independent screening
  # decisions and must not be pooled into one row.
  out <- boot_frequencies(fx_bag(), phase = fx_phase)
  expect_true("phase" %in% names(out))
  expect_setequal(out$phase, c("early", "late"))
  expect_identical(out$variable[out$term == "early.ln_age"], "ln_age")
  expect_identical(out$variable[out$term == "late.age"], "age")
  expect_identical(nrow(out), 4L)
})

test_that("a phase that is not a prefix leaves the variable alone", {
  # The package must not assume the phase label is the head of the term.
  # Only the caller's rule knows how terms are built.
  out <- boot_frequencies(fx_bag(), phase = function(term) "all")
  expect_true(all(out$phase == "all"))
  expect_identical(out$variable, out$term)
})

test_that("an accidental prefix is not stripped", {
  # A separator is required, not optional. A rule returning "e" for
  # `early.age` would otherwise yield `arly.age` -- a name that matches no
  # concept map and no cluster, and that nothing downstream can tell from a
  # real one. Leaving the term whole is unhelpful; mangling it is untrue.
  out <- boot_frequencies(fx_bag(), phase = function(term) "early")
  expect_identical(out$variable[out$term == "early.age"], "age")
  expect_identical(out$variable[out$term == "late.age"], "late.age")

  first_letter <- function(term) substr(term, 1L, 1L)
  out <- boot_frequencies(fx_bag(), phase = first_letter)
  expect_identical(out$variable, out$term)
})

test_that("any separator works, not just a dot", {
  # The package must not hardcode the separator either. Only its PRESENCE is
  # required; which character it is belongs to the caller's naming scheme.
  bag <- fx_bag()
  bag$boot$replicates$parameter <- sub("[.]", "_",
                                       bag$boot$replicates$parameter)
  out <- boot_frequencies(bag, phase = function(term) sub("_.*$", "", term))
  expect_identical(out$variable[out$term == "early_ln_age"], "ln_age")
})

test_that("boot_frequencies applies a scalar phase rule element by element", {
  # `bh` passes a vectorised sub(), but a rule written for one term must not
  # silently return one phase for the whole screen.
  one_at_a_time <- function(term) strsplit(term, ".", fixed = TRUE)[[1]][1]
  out <- boot_frequencies(fx_bag(), phase = one_at_a_time)
  expect_setequal(out$phase, c("early", "late"))
})

test_that("rows are ordered by phase, then descending frequency", {
  out <- boot_frequencies(fx_bag(), phase = fx_phase)
  expect_identical(out$term, c("early.age", "early.ln_age", "early.bmi",
                               "late.age"))
})

test_that("a screen that selected nothing yields no rows, not an error", {
  # boot_health() is where an empty screen is called a failure. This function
  # reports what is there.
  bag <- fx_bag_counts(list(), n_boot = 10L)
  out <- boot_frequencies(bag)
  expect_identical(nrow(out), 0L)
  expect_named(out, c("variable", "term", "n", "pct", "mc_error",
                      "near_threshold", "retained"))
})

test_that("boot_frequencies calls boot_validate and propagates its error", {
  bag <- fx_bag()
  bag$slstay <- NULL
  expect_error(boot_frequencies(bag), "slstay")
})

test_that("boot_frequencies refuses a phase argument that is not a rule", {
  expect_error(boot_frequencies(fx_bag(), phase = "early"), "function")
})

test_that("boot_dropped reports nothing dropped as zero rows", {
  out <- boot_dropped(fx_bag())
  expect_s3_class(out, "data.frame")
  expect_identical(nrow(out), 0L)
})

test_that("boot_dropped returns the candidates the screen never saw", {
  # A candidate the screen never saw cannot appear at any frequency, so its
  # absence from the frequency table is indistinguishable from never having
  # been selected. That is why this table exists at all.
  bag <- fx_bag()
  bag$dropped <- data.frame(
    variable = c("zexp", "agee", "bsa"),
    phase    = c("late", "early", "early"),
    reason   = c("constant", "all missing", "constant"),
    stringsAsFactors = FALSE
  )
  out <- boot_dropped(bag)
  expect_identical(nrow(out), 3L)
  expect_identical(out$variable, c("agee", "bsa", "zexp"))
  expect_named(out, c("variable", "phase", "reason"))
})

test_that("boot_dropped keeps whatever columns the runner wrote", {
  bag <- fx_bag()
  bag$dropped <- data.frame(variable = "zexp", reason = "constant",
                            n_missing = 4000L, stringsAsFactors = FALSE)
  out <- boot_dropped(bag)
  expect_true("n_missing" %in% names(out))
})

test_that("boot_dropped calls boot_validate and propagates its error", {
  bag <- fx_bag()
  bag$manifest <- NULL
  expect_error(boot_dropped(bag), "manifest")
})
