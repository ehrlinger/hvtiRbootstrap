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
