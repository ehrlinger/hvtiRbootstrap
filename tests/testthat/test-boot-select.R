sim_df <- function(n = 150, seed = 7) {
  set.seed(seed)
  x1 <- rnorm(n)
  data.frame(yc = 2 * x1 + rnorm(n), x1 = x1, x2 = rnorm(n), noise = rnorm(n))
}

test_that("boot_select returns one row per requested replicate", {
  out <- boot_select(sim_df(), yc ~ x1 + x2 + noise, fit_linear,
                     n_rep = 25, select = "none", seed = 42)
  expect_s3_class(out, "boot_selection")
  expect_equal(nrow(out$coefficients), 25L)
  expect_equal(out$n_rep, 25L)
})

test_that("unselected terms are NA, not zero -- this is what makes n a frequency", {
  out <- boot_select(sim_df(), yc ~ x1 + x2 + noise, fit_linear,
                     n_rep = 25, select = "stepwise", seed = 42)
  expect_true(anyNA(out$coefficients))
  expect_false(any(out$coefficients == 0, na.rm = TRUE))
})

test_that("every candidate term gets a column even if never selected", {
  out <- boot_select(sim_df(), yc ~ x1 + x2 + noise, fit_linear,
                     n_rep = 10, select = "stepwise", seed = 1)
  expect_true(all(c("x1", "x2", "noise") %in% colnames(out$coefficients)))
})

test_that("a failing replicate is retried, not counted -- %bootreg's regrc check", {
  # A fitter that fails the first 5 calls then succeeds. n_rep valid models must
  # still be produced, and n_attempts must exceed n_rep.
  calls <- 0
  flaky <- function(data, formula, select) {
    calls <<- calls + 1
    if (calls <= 5) return(NULL)
    fit_linear(data, formula, select)
  }
  out <- boot_select(sim_df(), yc ~ x1, flaky, n_rep = 10,
                     select = "none", seed = 3)
  expect_equal(nrow(out$coefficients), 10L)
  expect_gt(out$n_attempts, out$n_rep)
})

test_that("seed makes a run reproducible", {
  a <- boot_select(sim_df(), yc ~ x1 + x2, fit_linear, n_rep = 10,
                   select = "none", seed = 99)
  b <- boot_select(sim_df(), yc ~ x1 + x2, fit_linear, n_rep = 10,
                   select = "none", seed = 99)
  expect_equal(a$coefficients, b$coefficients)
})

test_that("fraction subsamples -- a DELIBERATE divergence from %bootreg", {
  # %bootreg computes `size = ds_size * fraction` at line 71, prints it at 72,
  # and never uses it: the resample loop at line 82 reads `do _counter=1 to
  # &ds_size`. FRACTION is documented but inert there. We implement it, because
  # a parameter that silently does nothing is a defect. See register entry D1.
  n_seen <- NULL
  spy <- function(data, formula, select) {
    n_seen <<- c(n_seen, nrow(data))
    fit_linear(data, formula, select)
  }
  boot_select(sim_df(n = 100), yc ~ x1, spy, n_rep = 3,
              fraction = 0.5, select = "none", seed = 5)
  expect_true(all(n_seen == 50))
})

test_that("a Cox run gets no phantom (Intercept) column", {
  skip_if_not_installed("survival")
  set.seed(11)
  df <- data.frame(time = rexp(120), status = rbinom(120, 1, 0.7),
                   x1 = rnorm(120), x2 = rnorm(120))
  out <- boot_select(df, survival::Surv(time, status) ~ x1 + x2, fit_cox,
                     n_rep = 5, select = "none", seed = 4)
  # Cox has no intercept. Hardcoding one would give an all-NA column that
  # boot_summary() reports as a variable with n = 0 -- a phantom term.
  expect_false("(Intercept)" %in% colnames(out$coefficients))
})

test_that("boot_select rejects a fraction outside (0, 1]", {
  expect_error(
    boot_select(sim_df(), yc ~ x1, fit_linear, n_rep = 2, fraction = 0),
    "`fraction` must be greater than 0 and at most 1", fixed = TRUE
  )
})

test_that("a fitter that always fails errors instead of looping forever -- D3", {
  # %bootreg would spin here indefinitely: &sample never advances and there is
  # no cap. Under R CMD check that is an unbounded hang with no diagnostic, so
  # boot_select() budgets attempts and reports what it managed.
  never <- function(data, formula, select) NULL
  expect_error(
    boot_select(sim_df(), yc ~ x1, never, n_rep = 10, select = "none",
                max_attempts = 25, seed = 1),
    "gave up after 25 attempts with 0 valid models of 10 requested",
    fixed = TRUE
  )
})

test_that("max_attempts = Inf restores %bootreg's uncapped loop", {
  # Not a hang: this fitter succeeds, so the loop terminates normally. The
  # assertion is that Inf is ACCEPTED, which is the documented escape hatch
  # back to exact macro behaviour.
  out <- boot_select(sim_df(), yc ~ x1, fit_linear, n_rep = 5,
                     select = "none", max_attempts = Inf, seed = 8)
  expect_equal(nrow(out$coefficients), 5L)
})
