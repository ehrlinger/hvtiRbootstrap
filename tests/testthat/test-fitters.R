make_df <- function(n = 200, seed = 1) {
  set.seed(seed)
  x1 <- rnorm(n)
  x2 <- rnorm(n)
  noise <- rnorm(n)
  data.frame(
    y  = as.integer(x1 + rnorm(n) > 0),
    yc = x1 * 2 + rnorm(n),
    x1 = x1, x2 = x2, noise = noise
  )
}

test_that("fit_linear returns a named numeric vector of kept coefficients", {
  out <- fit_linear(
    make_df(), yc ~ x1 + x2 + noise,
    list(method = "none", sle = 0.10, sls = 0.05, max_steps = 0)
  )
  expect_type(out, "double")
  expect_true(!is.null(names(out)))
  expect_true("x1" %in% names(out))
})

test_that("fit_logistic keeps only selected variables under stepwise", {
  out <- fit_logistic(
    make_df(), y ~ x1 + x2 + noise,
    list(method = "stepwise", sle = 0.10, sls = 0.05, max_steps = 0)
  )
  expect_type(out, "double")
  # x1 drives y by construction; pure noise should usually drop out. The
  # assertion is on the CONTRACT (a subset of the offered terms), not on which
  # variables win -- that is the model's business and varies by replicate.
  expect_true(all(names(out) %in% c("(Intercept)", "x1", "x2", "noise")))
})

test_that("stepwise actually drops terms rather than failing silently", {
  # Regression test. step() refits via environment(formula(object)) -- the
  # scope the FORMULA was written in, not the fitter's frame. A replicate's
  # `data` is not visible there, so R finds utils::data instead and the refit
  # errors; the fitter's tryCatch then turns that into NULL for every single
  # replicate. Asserting that selection genuinely narrows the model is what
  # keeps that failure from coming back disguised as "nothing was selected".
  ctrl <- list(method = "stepwise", sle = 0.10, sls = 0.05, max_steps = 0)
  out <- fit_linear(make_df(), yc ~ x1 + x2 + noise, ctrl)
  expect_false(is.null(out))
  expect_true("x1" %in% names(out))
  expect_lt(length(out), 4L)   # fewer than intercept + all three candidates
})

test_that("a fitter returns NULL rather than erroring on an impossible fit", {
  df <- make_df()
  df$y <- 0L                      # no variation in the response
  out <- fit_logistic(
    df, y ~ x1,
    list(method = "none", sle = 0.10, sls = 0.05, max_steps = 0)
  )
  expect_null(out)
})

test_that("fit_cox returns named coefficients without an intercept", {
  skip_if_not_installed("survival")
  set.seed(2)
  df <- data.frame(time = rexp(200), status = rbinom(200, 1, 0.7),
                   x1 = rnorm(200), x2 = rnorm(200))
  out <- fit_cox(df, survival::Surv(time, status) ~ x1 + x2,
                 list(method = "none", sle = 0.10, sls = 0.05, max_steps = 0))
  expect_type(out, "double")
  expect_false("(Intercept)" %in% names(out))
})

test_that("a converged fit is kept even when the engine warns", {
  # Regression: the fitters used to catch `warning` and return NULL, so a
  # replicate that converged with usable coefficients was thrown away whenever
  # glm emitted "fitted probabilities numerically 0 or 1". Quasi-separation is
  # common in bootstrap replicates, so discarding those biased the resample
  # against exactly the replicates where a predictor is strong. %bootreg gates
  # on &regrc, a return code SAS warnings do not set, so SAS keeps them too.
  set.seed(227)
  n <- 80
  x1 <- rnorm(n)
  x2 <- rnorm(n)
  d <- data.frame(y = rbinom(n, 1, plogis(4 * x1)), x1 = x1, x2 = x2)
  warned <- FALSE
  withCallingHandlers(
    fit <- stats::glm(y ~ x1 + x2, data = d, family = stats::binomial()),
    warning = function(w) {
      warned <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  expect_true(warned)          # the engine really does warn here
  expect_true(fit$converged)   # and the fit really is usable
  out <- fit_logistic(d, y ~ x1 + x2,
                      list(method = "none", sle = 0.10, sls = 0.05,
                           max_steps = 0))
  expect_false(is.null(out))
  expect_true("x1" %in% names(out))
})

test_that("a genuinely non-convergent logistic fit is still rejected", {
  d <- make_df()
  d$y <- 0L
  expect_null(fit_logistic(d, y ~ x1,
                           list(method = "none", sle = 0.10, sls = 0.05,
                                max_steps = 0)))
})

test_that("a fit that selected nothing is not confused with a failed fit", {
  # Cox has no intercept, so a replicate where selection kept no terms has
  # coef() of length zero. Returning NULL there made boot_select() treat a
  # legitimate "nothing was selected" outcome as a failure and redraw it,
  # dropping those replicates out of the pct denominator and inflating every
  # variable's selection frequency. lm/glm never hit this: the intercept
  # survives.
  skip_if_not_installed("survival")
  set.seed(4)
  m <- 150
  dc <- data.frame(time = rexp(m), status = rbinom(m, 1, 0.7))
  null_cox <- survival::coxph(survival::Surv(time, status) ~ 1, data = dc)
  out <- .coefs(null_cox)
  expect_false(is.null(out))
  expect_length(out, 0L)
})
