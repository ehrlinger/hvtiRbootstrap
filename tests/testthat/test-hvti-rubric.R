# Conformance with the hvtiR API rubric (vault: Projects/hvtiR API rubric.md).
# Each family package carries its own copy of the provenance check.

rubric_df <- function() {
  set.seed(8)
  n <- 80
  d <- data.frame(x1 = stats::rnorm(n), x2 = stats::rnorm(n))
  d$y <- d$x1 + stats::rnorm(n)
  d
}

expect_provenance_record <- function(p) {
  want <- c("package", "version", "sha", "method", "seed", "rng_kind", "time")
  testthat::expect_true(is.list(p))
  testthat::expect_true(all(want %in% names(p)))
  testthat::expect_true(is.character(p$package) && length(p$package) == 1L)
  testthat::expect_true(is.character(p$version) && length(p$version) == 1L)
  testthat::expect_true(is.character(p$sha) && length(p$sha) == 1L)
  testthat::expect_true(is.character(p$method) && length(p$method) >= 1L)
  testthat::expect_true(is.integer(p$seed) && length(p$seed) == 1L)
  testthat::expect_true(is.character(p$rng_kind) && length(p$rng_kind) == 3L)
  testthat::expect_true(inherits(p$time, "POSIXct") && length(p$time) == 1L)
}

test_that("boot_select(), boot_predict_ci() and boot_bag() emit the record", {
  fit <- boot_select(rubric_df(), y ~ x1 + x2, fit_linear, n_boot = 4,
                     seed = 3)
  expect_provenance_record(fit$provenance)
  expect_identical(fit$provenance$package, "hvtiRbootstrap")
  expect_identical(fit$provenance$method, "stepwise")
  expect_identical(fit$provenance$seed, 3L)
  expect_identical(fit$provenance$rng_kind, RNGkind())

  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 2L,
                  manifest = list(sha256 = "x"))
  expect_identical(bag$provenance, fit$provenance)

  r <- boot_predict_ci(rubric_df(), function(d, ...) c(m = mean(d$x1)),
                       n_boot = 5)
  expect_provenance_record(r$provenance)
  expect_identical(r$provenance$method, "percentile")
  expect_identical(r$provenance$seed, NA_integer_)
})

test_that("a screen from before the record gets NA, not today's facts", {
  fit <- boot_select(rubric_df(), y ~ x1, fit_linear, n_boot = 2, seed = 1)
  fit$provenance <- NULL
  fit$control$package <- "0.9.2"
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 1L,
                  manifest = list(sha256 = "x"))
  expect_provenance_record(bag$provenance)
  expect_identical(bag$provenance$version, "0.9.2")
  expect_true(all(is.na(bag$provenance$rng_kind)))
  expect_true(is.na(bag$provenance$time))
  expect_identical(bag$provenance$seed, 1L)
})

test_that("`n_rep` still works, warning once per session", {
  rm(list = ls(.deprecation_state), envir = .deprecation_state)
  withr::defer(rm(list = ls(.deprecation_state), envir = .deprecation_state))
  d <- rubric_df()
  expect_warning(
    fit <- boot_select(d, y ~ x1, fit_linear, n_rep = 3, seed = 1),
    class = "hvtiRbootstrap_deprecated"
  )
  expect_identical(fit$n_rep, 3L)
  # Once per session: the second call is quiet.
  expect_no_warning(boot_select(d, y ~ x1, fit_linear, n_rep = 3, seed = 1))
  # The same seed and count give the same screen under either name.
  same <- boot_select(d, y ~ x1, fit_linear, n_boot = 3, seed = 1)
  expect_identical(same$coefficients, fit$coefficients)

  expect_warning(
    r <- boot_predict_ci(d, function(x, ...) c(m = mean(x$x1)), n_rep = 4),
    class = "hvtiRbootstrap_deprecated"
  )
  expect_identical(r$n_rep, 4L)
})

test_that("boot_select() refuses both `n_boot` and `n_rep`", {
  expect_error(
    boot_select(rubric_df(), y ~ x1, fit_linear, n_boot = 3, n_rep = 3),
    class = "hvtiRbootstrap_bad_argument"
  )
})

test_that("errors a caller may catch carry hvtiRbootstrap_ classes", {
  expect_error(boot_validate(list()), class = "hvtiRbootstrap_invalid_bag")
  expect_error(boot_pool_chunks(list()), class = "hvtiRbootstrap_pool_refused")
  expect_error(boot_bag(list()), class = "hvtiRbootstrap_bag_refused")
  never <- function(data, formula, select) NULL
  expect_error(
    boot_select(rubric_df(), y ~ x1, never, n_boot = 2, max_attempts = 4),
    class = "hvtiRbootstrap_attempts_exhausted"
  )
  # Still base errors, and still printed without a call.
  e <- tryCatch(boot_validate(list()), error = identity)
  expect_s3_class(e, "error")
  expect_null(conditionCall(e))
})

test_that("a legacy call's `n_boot` still reaches `statistic` (#72 review)", {
  # Before the rename n_boot was forwarded through `...`. A call using the
  # old n_rep name must keep working exactly as it did for one release.
  rm(list = ls(.deprecation_state), envir = .deprecation_state)
  withr::defer(rm(list = ls(.deprecation_state), envir = .deprecation_state))
  seen <- integer(0)
  stat <- function(d, n_boot) {
    seen <<- c(seen, n_boot)
    c(m = mean(d$x1) + n_boot)
  }
  expect_warning(
    r <- boot_predict_ci(rubric_df(), stat, n_rep = 3, n_boot = 2, seed = 1),
    class = "hvtiRbootstrap_deprecated"
  )
  expect_identical(r$n_rep, 3L)
  expect_true(length(seen) >= 3L && all(seen == 2))
})
