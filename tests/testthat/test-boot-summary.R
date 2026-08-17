test_that("boot_summary reproduces %SUMBOOT on a fixed replicate table", {
  s <- boot_summary(fx_replicates())
  x1 <- s[s$variable == "x1", ]
  expect_equal(x1$n, 4L)
  expect_equal(x1$pct, 100)
  expect_equal(x1$mean, 2.5)
  expect_equal(x1$sd, stats::sd(c(1, 2, 3, 4)))
  expect_equal(x1$min, 1)
  expect_equal(x1$max, 4)

  x2 <- s[s$variable == "x2", ]
  expect_equal(x2$n, 2L)
  expect_equal(x2$pct, 50)
  expect_equal(x2$mean, 3)
  expect_equal(x2$sd, stats::sd(c(2, 4)))
})

test_that("a never-selected term is n = 0, pct = 0, statistics NA", {
  s <- boot_summary(fx_replicates())
  x3 <- s[s$variable == "x3", ]
  expect_equal(x3$n, 0L)
  expect_equal(x3$pct, 0)
  expect_true(is.na(x3$mean))
  expect_true(is.na(x3$sd))
})

test_that("rows are sorted by descending n, as %SUMBOOT's proc sort does", {
  s <- boot_summary(fx_replicates())
  expect_equal(s$variable, c("x1", "x2", "x3"))
  expect_true(!is.unsorted(rev(s$n)))
})

test_that("pct denominator is the replicate count, not the non-missing count", {
  # The distinction that makes pct a SELECTION FREQUENCY. If the denominator
  # were per-column non-missing, every pct would be 100.
  s <- boot_summary(fx_replicates())
  expect_false(all(s$pct == 100))
})

test_that("boot_summary accepts a boot_selection object as well as a matrix", {
  obj <- structure(
    list(coefficients = fx_replicates(), n_rep = 4L, n_attempts = 4L,
         call = quote(f())),
    class = "boot_selection"
  )
  expect_equal(boot_summary(obj), boot_summary(fx_replicates()))
})

test_that("boot_summary refuses input that is not replicate results", {
  expect_error(boot_summary(data.frame(a = 1)),
               "`x` must be a boot_selection object or a numeric matrix",
               fixed = TRUE)
})
