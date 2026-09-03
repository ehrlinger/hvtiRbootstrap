test_that(".interval_table returns bn's five quantities, named for coverage", {
  # %BNMNR ends with PCTLPTS=2.5 16 50 84 97.5 and names the results
  # CLL_P95 CLL_P68 MN_RES CLU_P68 CLU_P95. Coverage travels in the column
  # name, which is why no function here takes a confidence level.
  m <- matrix(1:100, ncol = 1, dimnames = list(NULL, "q"))

  tab <- .interval_table(m)

  expect_equal(names(tab), c("parameter", "cll_p95", "cll_p68", "median",
                             "clu_p68", "clu_p95"))
  expect_equal(tab$parameter, "q")
  # type 4 on 1..100 returns the requested percentile exactly.
  expect_equal(tab$cll_p95, 2.5)
  expect_equal(tab$cll_p68, 16)
  expect_equal(tab$median, 50)
  expect_equal(tab$clu_p68, 84)
  expect_equal(tab$clu_p95, 97.5)
})

test_that(".interval_table uses quantile type 4, which is SAS PCTLDEF=1", {
  # R's default is type 7. On 1..100 it returns 3.475 for P2.5 rather than
  # 2.5. Pinned so a later simplification to quantile(x, p) fails here.
  m <- matrix(1:100, ncol = 1, dimnames = list(NULL, "q"))

  expect_equal(.interval_table(m)$cll_p95, 2.5)
  expect_false(isTRUE(all.equal(.interval_table(m)$cll_p95, 3.475)))
})

test_that(".interval_table keeps one row per quantity, in column order", {
  # The names ARE the grid: %BNMNR evaluates its fitted curve on a thousand
  # points and takes percentiles down the replicates at each one. Row order
  # must follow the columns, or a caller plotting the result against its own
  # grid draws the band against the wrong x.
  m <- cbind(a = c(1, 2, 3, 4), b = c(10, 20, 30, 40), c = c(5, 5, 5, 5))

  tab <- .interval_table(m)

  expect_equal(tab$parameter, c("a", "b", "c"))
  expect_equal(nrow(tab), 3L)
  # A quantity that never varied has an interval of zero width, not an error.
  expect_equal(tab$cll_p95[tab$parameter == "c"], 5)
  expect_equal(tab$clu_p95[tab$parameter == "c"], 5)
})

test_that(".interval_table refuses NA rather than quietly narrowing a band", {
  # There is no NA semantics on this branch. On the SELECTION branch NA means
  # "this replicate did not choose this term" and is the whole design; here
  # nothing is chosen, so an NA is a broken replicate that boot_predict_ci()
  # should already have discarded. Taking a percentile over the rest would
  # silently use a smaller denominator -- which is exactly what SAS does, and
  # is the reading we decline.
  m <- matrix(c(1, 2, NA, 4), ncol = 1, dimnames = list(NULL, "q"))

  expect_error(.interval_table(m), "missing")
})

test_that(".interval_table needs column names, one per quantity", {
  # Every row is reported against a name. An unnamed matrix otherwise produced
  # a data frame with a NULL parameter column and a confusing recycling error.
  expect_error(.interval_table(matrix(1:4, ncol = 2)), "column names")
})

# A statistic with no randomness of its own, so a test can reason about it.
fx_statistic <- function(d, ...) c(mean = mean(d$x), max = max(d$x))

test_that("boot_predict_ci returns the replicates and their bands", {
  # The replicates are a DISTRIBUTION here, not a vote. $estimates is kept
  # because a caller may want a different quantity out of them, and
  # recomputing it means re-running the statistic.
  df <- data.frame(x = 1:50)

  r <- boot_predict_ci(df, fx_statistic, n_rep = 40, seed = 42)

  expect_s3_class(r, "boot_intervals")
  expect_equal(dim(r$estimates), c(40L, 2L))
  expect_equal(colnames(r$estimates), c("mean", "max"))
  expect_equal(r$n_rep, 40L)
  expect_equal(names(r$intervals), c("parameter", "cll_p95", "cll_p68",
                                     "median", "clu_p68", "clu_p95"))
  expect_equal(r$intervals$parameter, c("mean", "max"))
})

test_that("boot_predict_ci counts VALID replicates, redrawing failures", {
  # %BNMNR increments &SAMPLE only when the fit produced the expected
  # parameters, so RESAMPL= counts valid results and a failure is redrawn in
  # place. n_attempts records what it cost.
  df <- data.frame(x = 1:50)
  i <- 0L
  flaky <- function(d, ...) {
    i <<- i + 1L
    if (i %% 2L == 0L) NULL else c(mean = mean(d$x))
  }

  r <- boot_predict_ci(df, flaky, n_rep = 10, seed = 1)

  expect_equal(r$n_rep, 10L)
  expect_equal(nrow(r$estimates), 10L)
  expect_gt(r$n_attempts, 10L)
})

test_that("a statistic returning NA is a failed replicate, not a gap", {
  # There is no NA semantics on this branch. A statistic that converged to a
  # missing estimate has not produced a usable replicate, and keeping it would
  # narrow the band at that quantity.
  df <- data.frame(x = 1:50)
  i <- 0L
  sometimes_na <- function(d, ...) {
    i <<- i + 1L
    c(mean = if (i %% 2L == 0L) NA_real_ else mean(d$x))
  }

  r <- boot_predict_ci(df, sometimes_na, n_rep = 5, seed = 1)

  expect_equal(r$n_rep, 5L)
  expect_false(anyNA(r$estimates))
  expect_gt(r$n_attempts, 5L)
})

test_that("NaN, Inf and -Inf are each a failed replicate too", {
  # The guard in `one()` drops non-finite values via is.finite() alone, with
  # no separate anyNA() clause -- confirm all four non-finite kinds still get
  # redrawn rather than stored, one bad value at a time.
  df <- data.frame(x = 1:50)
  bad_values <- c(NaN, Inf, -Inf)

  for (bad in bad_values) {
    i <- 0L
    sometimes_bad <- function(d, ...) {
      i <<- i + 1L
      c(mean = if (i %% 2L == 0L) bad else mean(d$x))
    }

    r <- boot_predict_ci(df, sometimes_bad, n_rep = 5, seed = 1)

    expect_equal(r$n_rep, 5L)
    expect_true(all(is.finite(r$estimates)))
    expect_gt(r$n_attempts, 5L)
  }
})

test_that("a statistic whose names change is a failed replicate", {
  # %BNMNR compares the bootstrap fit's PARAMETER COUNT against the reference
  # and resamples when they differ. Names are stricter than a count: a count
  # can match while the names do not, and then one row of the percentile table
  # is assembled from two different quantities.
  df <- data.frame(x = 1:50)
  i <- 0L
  drifting <- function(d, ...) {
    i <<- i + 1L
    if (i %% 3L == 0L) c(other = 1) else c(mean = mean(d$x))
  }

  r <- boot_predict_ci(df, drifting, n_rep = 6, seed = 1)

  expect_equal(colnames(r$estimates), "mean")
  expect_equal(r$n_rep, 6L)
})

test_that("boot_predict_ci is reproducible and restores the caller's stream", {
  # Seeding is a global side effect. boot_select() puts the caller's stream
  # back and so must this, or a script that seeds once at the top loses
  # reproducibility from the first call onward.
  df <- data.frame(x = 1:50)

  a <- boot_predict_ci(df, fx_statistic, n_rep = 20, seed = 7)
  b <- boot_predict_ci(df, fx_statistic, n_rep = 20, seed = 7)
  expect_equal(a$estimates, b$estimates)

  set.seed(99)
  before <- .Random.seed
  invisible(boot_predict_ci(df, fx_statistic, n_rep = 5, seed = 3))
  expect_equal(.Random.seed, before)
})

test_that("boot_predict_ci passes ... through to the statistic", {
  df <- data.frame(x = 1:50)
  scaled <- function(d, k, ...) c(mean = mean(d$x) * k)

  r <- boot_predict_ci(df, scaled, n_rep = 10, seed = 1, k = 10)

  expect_true(all(r$estimates[, "mean"] > 100))
})

test_that("fraction draws a smaller sample, as %BNMNR actually does", {
  # Unlike %bootreg, which computes ds_size * fraction and then draws ds_size
  # anyway, %BNMNR sets &SIZE and draws that many. No divergence to register
  # on this branch.
  df <- data.frame(x = 1:100)
  n_seen <- function(d, ...) c(n = nrow(d))

  r <- boot_predict_ci(df, n_seen, n_rep = 5, fraction = 0.25, seed = 1)

  expect_true(all(r$estimates[, "n"] == 25))
})

test_that("boot_predict_ci guards its inputs", {
  df <- data.frame(x = 1:10)

  expect_error(boot_predict_ci(df, fx_statistic, n_rep = 0),
               "positive whole number")
  expect_error(boot_predict_ci(df, fx_statistic, n_rep = 5, fraction = 0),
               "greater than 0")
  expect_error(boot_predict_ci(df, "not a function", n_rep = 5),
               "must be a function")
  expect_error(boot_predict_ci(data.frame(), fx_statistic, n_rep = 5),
               "at least one row")
  # No coverage argument exists anywhere in this package, by design. `...` is
  # forwarded to `statistic`, so a `conf =` would otherwise be silently
  # absorbed by any statistic declaring `...` -- which fx_statistic itself
  # does, and it is refused by name before that can happen.
  expect_error(boot_predict_ci(df, fx_statistic, n_rep = 5, conf = 0.95),
               "no coverage argument")
})

test_that("boot_intervals prints its counts and summarises to the bands", {
  df <- data.frame(x = 1:50)
  r <- boot_predict_ci(df, fx_statistic, n_rep = 20, seed = 1)

  expect_output(print(r), "boot_intervals")
  expect_output(print(r), "20")
  expect_equal(summary(r), r$intervals)
})

test_that("id draws whole units, not rows", {
  # %BNMNR bootstraps PATIENTS from INDAT and then joins INMULT to pull that
  # patient's repeated records. Drawing rows instead would break the
  # within-unit correlation the design exists to respect.
  d <- data.frame(pt = rep(1:5, each = 4), x = 1)
  seen <- function(dd, ...) c(rows = nrow(dd), units = length(unique(dd$pt)))

  r <- boot_predict_ci(d, seen, n_rep = 10, id = "pt", seed = 1)

  # Five units drawn with replacement, four rows each: always 20 rows, and
  # never more than 5 distinct original units.
  expect_true(all(r$estimates[, "rows"] == 20))
  expect_true(all(r$estimates[, "units"] <= 5))
  expect_true(any(r$estimates[, "units"] < 5))
})

test_that("a unit drawn twice becomes two distinct units", {
  # THE POINT OF RENUMBERING. %BNMNR assigns _PTID=_COUNTER before the join and
  # then fits random u ~ normal(0,...) subject=_PTID. Without it the two copies
  # share a random effect and the resample UNDERSTATES between-unit variance --
  # the quantity a bootstrap exists to estimate.
  d <- data.frame(pt = rep(1:3, each = 2), x = 1)
  probe <- function(dd, ...) {
    c(orig = length(unique(dd$pt)), drawn = length(unique(dd$.boot_unit)))
  }

  r <- boot_predict_ci(d, probe, n_rep = 30, id = "pt", seed = 3)

  # .boot_unit is always the number of DRAWS; pt can be fewer when a unit was
  # drawn twice. If they were ever equal by construction the renumbering would
  # be doing nothing.
  expect_true(all(r$estimates[, "drawn"] == 3))
  expect_true(any(r$estimates[, "orig"] < 3))
})

test_that("fraction applies to units, not rows", {
  # &SIZE=&DS_SIZE*&FRACTION is computed from the patient-level INDAT.
  d <- data.frame(pt = rep(1:10, each = 3), x = 1)
  seen <- function(dd, ...) {
    c(units = length(unique(dd$.boot_unit)), rows = nrow(dd))
  }

  r <- boot_predict_ci(d, seen, n_rep = 5, id = "pt", fraction = 0.5, seed = 1)

  expect_true(all(r$estimates[, "units"] == 5))
  expect_true(all(r$estimates[, "rows"] == 15))
})

test_that("id must name a column, and .boot_unit must not already exist", {
  d <- data.frame(pt = rep(1:3, each = 2), x = 1)
  est <- function(dd, ...) c(m = mean(dd$x))

  expect_error(boot_predict_ci(d, est, n_rep = 2, id = "nope"),
               "not a column")
  # Silently overwriting it would change the caller's data underneath their
  # own statistic.
  d2 <- cbind(d, .boot_unit = 1L)
  expect_error(boot_predict_ci(d2, est, n_rep = 2, id = "pt"),
               "\\.boot_unit")
})

test_that("a single unit, numeric id >= 1, avoids sample()'s footgun", {
  # sample(units, ...) misreads a length-1 numeric id >= 1 as sample(1:id,
  # ...): a single patient coded 7 would draw from 1:7 and match no rows.
  # sample.int() over positions, not values, cannot make that mistake.
  d <- data.frame(pt = rep(7, 4), x = 1:4)
  est <- function(dd, ...) c(m = mean(dd$x))

  r <- boot_predict_ci(d, est, n_rep = 5, id = "pt", seed = 1)

  expect_equal(r$n_rep, 5L)
  expect_false(anyNA(r$estimates))
  expect_equal(r$control$n_units, 1L)
})

test_that("an id column containing NA is refused", {
  # split() drops NA-grouped rows silently. An id-less unit is meaningless
  # either way, but silently dropping rows from a resample is worse than
  # refusing outright.
  d <- data.frame(pt = c(1, 2, NA, 2), x = 1:4)
  est <- function(dd, ...) c(m = mean(dd$x))

  expect_error(boot_predict_ci(d, est, n_rep = 2, id = "pt"), "NA")
})

test_that("the control record names the resampling unit", {
  d <- data.frame(pt = rep(1:4, each = 2), x = 1)
  est <- function(dd, ...) c(m = mean(dd$x))

  r <- boot_predict_ci(d, est, n_rep = 5, id = "pt", seed = 1)

  expect_equal(r$control$id, "pt")
  expect_equal(r$control$n_units, 4L)
  expect_equal(r$control$n_rows, 8L)
})
