# A small screen with a known answer, so the round-trip below is checkable by
# hand. Synthetic: no cohort data enters this package.
fx_selection <- function(n_rep = 20) {
  set.seed(11)
  n  <- 150
  x1 <- stats::rnorm(n)
  x2 <- stats::rnorm(n)
  df <- data.frame(y = 2 * x1 + stats::rnorm(n), x1 = x1, x2 = x2,
                   noise = stats::rnorm(n))
  boot_select(df, y ~ x1 + x2 + noise, fit_linear, n_rep = n_rep,
              sle = 0.10, sls = 0.05, seed = 42)
}

test_that("boot_bag() produces a bag the reporting layer accepts", {
  fit <- fx_selection()
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 5L,
                  manifest = list(sha256 = "abc123"))

  expect_silent(boot_validate(bag))
  expect_identical(bag$n_boot, 20L)
  expect_identical(bag$slentry, 0.10)
  expect_identical(bag$slstay, 0.05)
  expect_identical(bag$seed, 42)
  expect_identical(bag$n_rows, 150L)
  expect_identical(bag$requested, 5L)
  expect_identical(bag$usable, 3L)          # x1, x2, noise
  expect_identical(bag$boot$n_success, 20L)
  expect_identical(bag$boot$n_failed, fit$n_attempts - 20L)
})

test_that("the wide-to-long pivot round-trips exactly", {
  fit <- fx_selection()
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 5L,
                  manifest = list(sha256 = "abc123"))

  # The invariant that matters: the frequencies the report shows must be the
  # frequencies boot_summary() computes from the matrix. A pivot that lost a
  # replicate, or that wrote an NA as a row, would move them and nothing
  # downstream could see it.
  wide <- boot_summary(fit)
  wide <- wide[wide$variable != "(Intercept)", , drop = FALSE]
  freq <- boot_frequencies(bag)

  expect_setequal(freq$variable, wide$variable)
  expect_equal(freq$pct[order(freq$variable)],
               wide$pct[order(wide$variable)], tolerance = 1e-12)
  expect_equal(freq$n[order(freq$variable)], wide$n[order(wide$variable)])
})

test_that("an unselected term stays absent rather than becoming a row", {
  # The reason the pivot drops NA. boot_frequencies() counts a term's rows
  # against n_boot, so a row written for a term the replicate did not select
  # would be counted as a selection and every frequency would rise.
  fit <- fx_selection()
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 5L,
                  manifest = list(sha256 = "abc123"))
  expect_identical(nrow(bag$boot$replicates),
                   sum(!is.na(fit$coefficients)))
  expect_false(anyNA(bag$boot$replicates$estimate))
})

test_that("boot_bag() carries no phase dimension", {
  fit <- fx_selection()
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 5L,
                  manifest = list(sha256 = "abc123"))

  # The whole reason bl, br and bc are thin templates. phase = NULL is the
  # default and must produce no phase column anywhere.
  expect_false("phase" %in% names(boot_frequencies(bag)))
  cm <- data.frame(variable = c("x1", "x2", "noise"),
                   concept = c("x", "x", "noise"),
                   stringsAsFactors = FALSE)
  expect_false("phase" %in% names(boot_concepts(bag, cm)))
  expect_identical(nrow(boot_dropped(bag)), 0L)
  expect_true(all(c("Distinct candidates ever selected",
                    "SD of the first free base parameter") %in%
                    boot_health(bag)$check))
})

test_that("an unseeded screen is refused, not given a blank seed", {
  set.seed(9)
  df <- data.frame(y = stats::rnorm(80), x1 = stats::rnorm(80))
  fit <- boot_select(df, y ~ x1, fit_linear, n_rep = 4, select = "none")
  expect_error(
    boot_bag(fit, base_params = "(Intercept)", requested = 1L,
             manifest = list(sha256 = "a")),
    "did not record a seed"
  )
})

test_that("a boot_selection from before 0.9.2 is refused by name", {
  fit <- fx_selection()
  fit$control <- NULL
  expect_error(
    boot_bag(fit, base_params = "(Intercept)", requested = 5L,
             manifest = list(sha256 = "a")),
    "predates"
  )
})

test_that("a usable count that disagrees with the screen is refused", {
  fit <- fx_selection()
  expect_error(
    boot_bag(fit, base_params = "(Intercept)", requested = 5L,
             manifest = list(sha256 = "a"), usable = 9L),
    "9 usable candidates"
  )
})

test_that("base_params must name a term the screen actually carries", {
  fit <- fx_selection()
  expect_error(
    boot_bag(fit, base_params = "not_a_term", requested = 5L,
             manifest = list(sha256 = "a")),
    "not among the screen's terms"
  )
})

test_that("dropped is carried through when supplied", {
  fit <- fx_selection()
  drp <- data.frame(variable = "constant_col", reason = "constant",
                    stringsAsFactors = FALSE)
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 6L,
                  manifest = list(sha256 = "a"), dropped = drp)
  expect_identical(nrow(boot_dropped(bag)), 1L)
})

test_that("a Cox screen has no intercept, and boot_bag() says so usefully", {
  # The failure bc's template warns about. A logistic runner's base_params
  # copied to a Cox screen names a term that does not exist, and every
  # frequency excludes the base model, so a name matching nothing would
  # exclude nothing and report the base model as a candidate.
  skip_if_not_installed("survival")
  set.seed(5)
  n <- 200
  x1 <- stats::rnorm(n)
  d <- data.frame(x1 = x1, x2 = stats::rnorm(n),
                  t = stats::rexp(n, exp(0.3 * x1) / 10),
                  e = stats::rbinom(n, 1, 0.7))
  fit <- boot_select(d, survival::Surv(t, e) ~ x1 + x2, fit_cox,
                     n_rep = 6, seed = 3)
  expect_false("(Intercept)" %in% colnames(fit$coefficients))
  expect_error(
    boot_bag(fit, base_params = "(Intercept)", requested = 2L,
             manifest = list(sha256 = "a")),
    "not among the screen's terms"
  )
})

test_that("a control with no seed gives the diagnosis, not a length error", {
  # is.na(NULL) is logical(0), and `if (logical(0))` errors with "argument is
  # of length zero" -- which replaces the message below with one naming
  # nothing. Raised by Copilot on the PR that added boot_bag().
  fit <- fx_selection()
  fit$control$seed <- NULL
  expect_error(
    boot_bag(fit, base_params = "(Intercept)", requested = 5L,
             manifest = list(sha256 = "a")),
    "did not record a seed"
  )
})

test_that("fractional counts are refused, not silently truncated", {
  # as.integer(5.7) is 5. The pool a frequency is conditional on would then be
  # under-reported by a number nobody chose. boot_select() guards n_rep the
  # same way.
  fit <- fx_selection()
  expect_error(
    boot_bag(fit, base_params = "(Intercept)", requested = 5.7,
             manifest = list(sha256 = "a")),
    "`requested` must be a single whole number"
  )
  expect_error(
    boot_bag(fit, base_params = "(Intercept)", requested = 5L,
             manifest = list(sha256 = "a"), usable = 3.2),
    "`usable` must be a single whole number"
  )
})
