test_that(".pv_enter_p uses partial F for lm, matching PROC REG", {
  # PROC REG SELECTION=STEPWISE tests partial F to enter. anova(test = "F")
  # is that test; this pins the value rather than the call, so a later switch
  # to a chi-square would fail here.
  set.seed(1)
  d <- data.frame(y = rnorm(60), x1 = rnorm(60), x2 = rnorm(60))
  base <- lm(y ~ x1, d)
  want <- anova(base, lm(y ~ x1 + x2, d), test = "F")[["Pr(>F)"]][2]

  expect_equal(.pv_enter_p(base, "x2", d, "f"), want)
})

test_that(".pv_enter_p uses the Rao score test for glm, matching LOGISTIC", {
  # PROC LOGISTIC enters on the score chi-square. anova.glm(test = "Rao") is a
  # genuine score test -- it differs from the LR test -- so this asserts BOTH
  # that we get Rao and that Rao is not silently LR.
  set.seed(2)
  d <- data.frame(y = rbinom(200, 1, 0.4), x1 = rnorm(200), x2 = rnorm(200))
  base <- glm(y ~ x1, binomial(), d)
  full <- glm(y ~ x1 + x2, binomial(), d)
  rao <- anova(base, full, test = "Rao")[["Pr(>Chi)"]][2]
  lr <- anova(base, full, test = "LRT")[["Pr(>Chi)"]][2]

  expect_equal(.pv_enter_p(base, "x2", d, "rao"), rao)
  expect_false(isTRUE(all.equal(rao, lr)))
})

test_that(".pv_remove_p gives ONE p-value per term, not per coefficient", {
  # A three-level factor contributes two coefficients and PROC tests the term
  # with a multi-df Wald chi-square. Reading one coefficient's Pr(>|z|) would
  # be wrong for every factor in every screen, and would silently look right
  # for numeric terms.
  set.seed(3)
  d <- data.frame(y = rbinom(300, 1, 0.5), x1 = rnorm(300),
                  g = factor(sample(c("a", "b", "c"), 300, TRUE)))
  fit <- glm(y ~ x1 + g, binomial(), d)

  p <- .pv_remove_p(fit, "wald")

  expect_setequal(names(p), c("x1", "g"))
  expect_length(p, 2L)
  expect_true(all(p >= 0 & p <= 1, na.rm = TRUE))
})

test_that(".pv_remove_p's multi-df Wald is the quadratic form, not a t-test", {
  # W = b' V^-1 b on length(b) degrees of freedom. Computed here independently
  # so the test fails if the implementation quietly drops to one coefficient.
  set.seed(4)
  d <- data.frame(y = rbinom(300, 1, 0.5), x1 = rnorm(300),
                  g = factor(sample(c("a", "b", "c"), 300, TRUE)))
  fit <- glm(y ~ x1 + g, binomial(), d)
  j <- which(attr(stats::model.matrix(fit), "assign") == 2L)
  b <- stats::coef(fit)[j]
  v <- stats::vcov(fit)[j, j, drop = FALSE]
  want <- stats::pchisq(drop(t(b) %*% solve(v) %*% b), length(b),
                        lower.tail = FALSE)

  expect_equal(unname(.pv_remove_p(fit, "wald")[["g"]]), want)
})

test_that("an uncomputable test is NA, not an error", {
  # A singular or non-converging candidate must not kill the replicate. The
  # driver treats NA as "cannot enter" and moves on; an error would propagate
  # to the fitter's tryCatch and discard a replicate that was fine.
  set.seed(5)
  d <- data.frame(y = rnorm(20), x1 = rnorm(20))
  d$dup <- d$x1
  base <- lm(y ~ x1, d)

  expect_true(is.na(.pv_enter_p(base, "nonesuch", d, "f")))
})

test_that(".pv_enter_p returns a p-value on a warning, not NA", {
  # A quasi-separated candidate converges to usable coefficients while glm
  # warns "fitted probabilities numerically 0 or 1". Catching that warning
  # (as a prior version of .pv_enter_p did) returns NA and the stepwise
  # driver treats NA as "cannot enter" -- refusing entry to exactly the
  # candidates where a predictor is strong, biasing the whole screen against
  # the strongest predictors. x2 here separates y almost perfectly, so the
  # refit warns but converges, and the entry p-value must be a real,
  # overwhelmingly small number.
  set.seed(1)
  n <- 100
  x1 <- rnorm(n)
  x2 <- rnorm(n)
  y <- rbinom(n, 1, stats::plogis(10 * x2))
  d <- data.frame(y = y, x1 = x1, x2 = x2)
  base <- glm(y ~ x1, binomial(), d)

  expect_warning(
    bigger <- stats::update(base, y ~ x1 + x2, data = d),
    "fitted probabilities numerically 0 or 1"
  )
  expect_true(bigger$converged)

  # The warning above already proves the refit warns; .pv_enter_p must not
  # catch it, so it is expected to surface here too -- suppressed since the
  # point of this call is the returned p-value, not a second assertion.
  p <- suppressWarnings(.pv_enter_p(base, "x2", d, "rao"))

  expect_false(is.na(p))
  expect_lt(p, 1e-6)
})

test_that(".pv_stepwise starts empty and adds, as PROC does", {
  # SELECTION=STEPWISE begins with an intercept and adds. stats::step() began
  # at the FULL model and dropped, which is a different algorithm that can
  # settle somewhere else -- a second divergence underneath #32.
  set.seed(11)
  n <- 400
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n), junk = rnorm(n))
  d$y <- 2 * d$x1 + rnorm(n)
  full <- lm(y ~ x1 + x2 + junk, d)

  got <- .pv_stepwise(full, d, sle = 0.05, sls = 0.05, max_steps = 0,
                      enter = "f", remove = "f")

  kept <- attr(stats::terms(got), "term.labels")
  expect_true("x1" %in% kept)
  expect_false("junk" %in% kept)
})

test_that("sle actually gates entry", {
  # The test #32 exists for. At sle = 0 nothing can enter, so the result is
  # the intercept-only base. If sle were ignored the screen would still pick
  # up x1, which is overwhelming here.
  set.seed(12)
  n <- 300
  d <- data.frame(x1 = rnorm(n))
  d$y <- 3 * d$x1 + rnorm(n)
  full <- lm(y ~ x1, d)

  got <- .pv_stepwise(full, d, sle = 0, sls = 0.05, max_steps = 0,
                      enter = "f", remove = "f")

  expect_length(attr(stats::terms(got), "term.labels"), 0L)
})

test_that("sls actually gates removal", {
  # sls is the level to STAY: a term leaves when its p-value EXCEEDS it. So
  # sls = 1 keeps everything and a small sls throws the weak term out. Getting
  # this backwards would be easy and would still pass a test that only ever
  # asserted "something was removed".
  #
  # sle = 1 admits every candidate, so sls is the only thing that can explain
  # what is missing at the end. Pinned separately from sle so that honouring
  # one and ignoring the other is a failure.
  set.seed(13)
  n <- 300
  d <- data.frame(x1 = rnorm(n), junk = rnorm(n))
  d$y <- 3 * d$x1 + rnorm(n)
  full <- lm(y ~ x1 + junk, d)

  loose <- .pv_stepwise(full, d, sle = 1, sls = 1, max_steps = 0,
                        enter = "f", remove = "f")
  tight <- .pv_stepwise(full, d, sle = 1, sls = 0.001, max_steps = 0,
                        enter = "f", remove = "f")

  expect_true("junk" %in% attr(stats::terms(loose), "term.labels"))
  expect_false("junk" %in% attr(stats::terms(tight), "term.labels"))
  expect_true("x1" %in% attr(stats::terms(tight), "term.labels"))
})

test_that("a term removed once does not immediately re-enter", {
  # SAS ends the screen when the term about to enter is the one just removed.
  # With sle > sls that cycle is not exotic, it is the default outcome: the
  # term clears the entry threshold, fails the stricter stay threshold, leaves,
  # and is the best candidate again. Without the guard only the step budget
  # ends it, and the answer depends on which half of the cycle it stopped on.
  set.seed(16)
  n <- 300
  d <- data.frame(x1 = rnorm(n), junk = rnorm(n))
  d$y <- 3 * d$x1 + rnorm(n)
  full <- lm(y ~ x1 + junk, d)

  t0 <- proc.time()[["elapsed"]]
  got <- .pv_stepwise(full, d, sle = 1, sls = 0.001, max_steps = 0,
                      enter = "f", remove = "f")
  elapsed <- proc.time()[["elapsed"]] - t0

  # It must settle, not spin to a 1000-step budget.
  expect_lt(elapsed, 20)
  expect_equal(attr(stats::terms(got), "term.labels"), "x1")
})

test_that(".pv_stepwise terminates and honours max_steps", {
  # A budget, as %bootreg's MAXSTEP= is. The loop must also terminate on its
  # own when nothing enters or leaves, or a screen that oscillates between two
  # terms would run until the budget rather than settling.
  set.seed(14)
  n <- 200
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n))
  d$y <- d$x1 + d$x2 + rnorm(n)
  full <- lm(y ~ x1 + x2, d)

  one <- .pv_stepwise(full, d, sle = 0.5, sls = 0.5, max_steps = 1,
                      enter = "f", remove = "f")
  expect_lte(length(attr(stats::terms(one), "term.labels")), 1L)

  settled <- .pv_stepwise(full, d, sle = 0.5, sls = 0.5, max_steps = 0,
                          enter = "f", remove = "f")
  expect_s3_class(settled, "lm")
})

test_that(".pv_stepwise drives glm and coxph, not only lm", {
  # The three fitters each hand it a different model class.
  set.seed(15)
  n <- 400
  d <- data.frame(x1 = rnorm(n), junk = rnorm(n))
  d$y <- rbinom(n, 1, plogis(1.5 * d$x1))
  g <- .pv_stepwise(glm(y ~ x1 + junk, binomial(), d), d, 0.05, 0.05, 0,
                    enter = "rao", remove = "wald")

  expect_s3_class(g, "glm")
  expect_true("x1" %in% attr(stats::terms(g), "term.labels"))

  skip_if_not_installed("survival")
  d$t <- rexp(n, exp(0.8 * d$x1))
  d$s <- rbinom(n, 1, 0.7)
  cx <- .pv_stepwise(
    survival::coxph(survival::Surv(t, s) ~ x1 + junk, d), d,
    0.05, 0.05, 0, enter = "lr", remove = "wald"
  )
  expect_s3_class(cx, "coxph")
})

test_that("a candidate with a missing value is still reachable", {
  # Regression test. update(fit, . ~ . + term, data = data) drops rows
  # missing `term` from the bigger model but not from the base, so anova()
  # errors with "models were not all fitted to the same size of dataset".
  # .pv_enter_p() catches that and returns NA, which the driver reads as
  # "cannot enter" -- and since the screen starts intercept-only, that fires
  # on the very first forward step and every step after, making the term
  # unreachable for the whole run. Every other fixture in this file is
  # complete-case, which is why the rest of the file does not catch this.
  set.seed(31)
  n <- 400
  x1 <- rnorm(n)
  x2 <- rnorm(n)
  d <- data.frame(x1 = x1, x2 = x2)
  d$y <- 3 * x1 + 2 * x2 + rnorm(n)
  d$x2[1:8] <- NA
  full <- lm(y ~ x1 + x2, d)

  got <- .pv_stepwise(full, d, sle = 0.05, sls = 0.05, max_steps = 0,
                      enter = "f", remove = "f")

  expect_true("x2" %in% attr(stats::terms(got), "term.labels"))
})

test_that("a base that fails to refit returns NULL, not the full model", {
  # Regression test for the intercept-only fallback. Returning `fit` here
  # would carry every offered term into the replicate's coefficient row,
  # indistinguishable from a screen that genuinely selected everything --
  # inflating every term's selection frequency instead of failing loud.
  set.seed(32)
  n <- 30
  d <- data.frame(x1 = rnorm(n))
  d$y <- d$x1 + rnorm(n)
  full <- lm(y ~ x1, d)

  # A `data` with none of the model's own rows left makes the
  # intercept-only refit fail: nrow(data) == 0 after complete.cases().
  d_empty <- d[0, , drop = FALSE]

  got <- .pv_stepwise(full, d_empty, sle = 0.05, sls = 0.05, max_steps = 0,
                      enter = "f", remove = "f")

  expect_null(got)
})
