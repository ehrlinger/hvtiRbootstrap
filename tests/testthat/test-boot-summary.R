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

test_that("a matrix without column names is refused clearly", {
  # The documented input is "a numeric matrix", and an unnamed one used to die
  # inside data.frame() with "arguments imply differing number of rows: 0, 2".
  expect_error(
    boot_summary(matrix(c(1, 2, NA, 4), nrow = 2)),
    "`x` must have column names, one per candidate term", fixed = TRUE
  )
})

test_that(".bag_summary keys on parameter and adds the quantile columns", {
  # fx_replicates(): x1 = c(1,2,3,4), x2 = c(2,NA,4,NA), x3 all NA.
  s <- .bag_summary(fx_replicates())

  expect_equal(names(s), c("parameter", "n", "pct", "mean", "sd", "min",
                           "max", "sel_q025", "sel_q975"))
  # `variable` is boot_summary()'s key. The bag reads `parameter`, and a bag
  # carrying both would let a renderer pick either and be right by accident.
  expect_false("variable" %in% names(s))
  expect_equal(s$parameter, c("x1", "x2", "x3"))
  expect_equal(s$n, c(4L, 2L, 0L))
})

test_that(".bag_summary computes the quantiles conditional on selection", {
  # x2 is selected in 2 of 4 replicates, so its quantiles are over c(2, 4) --
  # the replicates that SELECTED it -- not over four values with two zeros.
  # That is what makes these selection-branch statistics rather than a CI,
  # and it is why they are not named ci_lower/ci_upper.
  s <- .bag_summary(fx_replicates())

  expect_equal(s$sel_q025[s$parameter == "x1"], 1.0)
  expect_equal(s$sel_q975[s$parameter == "x1"], 3.9)
  expect_equal(s$sel_q025[s$parameter == "x2"], 2.0)
  expect_equal(s$sel_q975[s$parameter == "x2"], 3.9)
})

test_that(".bag_summary uses quantile type 4, which is SAS PCTLDEF=1", {
  # R's default is type 7 and SAS PROC STDIZE's is PCTLDEF=1. On four
  # replicates the two disagree in the third digit; at the interval branch's
  # hundred they disagree by a few per cent of interval width. Pinned here so
  # a later simplification to quantile(x, p) is a test failure.
  s <- .bag_summary(fx_replicates())

  expect_equal(s$sel_q025[s$parameter == "x1"], 1.0)
  expect_false(isTRUE(all.equal(s$sel_q025[s$parameter == "x1"], 1.075)))
  expect_equal(s$sel_q025[s$parameter == "x2"], 2.0)
  expect_false(isTRUE(all.equal(s$sel_q025[s$parameter == "x2"], 2.05)))
})

test_that(".bag_summary yields NA, not an error, for a term never selected", {
  # x3 is NA in every replicate. quantile() of nothing is NA; zero would be a
  # claim about a coefficient that no model ever estimated.
  s <- .bag_summary(fx_replicates())

  expect_true(is.na(s$sel_q025[s$parameter == "x3"]))
  expect_true(is.na(s$sel_q975[s$parameter == "x3"]))
  expect_equal(s$n[s$parameter == "x3"], 0L)
})

test_that(".bag_summary matches quantiles to their own column, not by name", {
  # match(out$parameter, colnames(m)) used to return the FIRST hit for a
  # name, so two identically-named columns could take a row's quantiles
  # from a different column than its own mean/sd/min/max came from. Column
  # 2 ("a") is entirely larger than column 1 ("a"); if its row took column
  # 1's quantiles instead, they would fall far outside its own min/max.
  m <- matrix(c(1, 2, 10, 20), nrow = 2, dimnames = list(NULL, c("a", "a")))
  s <- .bag_summary(m)

  expect_equal(s$mean, c(1.5, 15))
  expect_equal(s$sel_q025[s$mean == 1.5],
               unname(stats::quantile(c(1, 2), 0.025, type = 4)))
  expect_equal(s$sel_q025[s$mean == 15],
               unname(stats::quantile(c(10, 20), 0.025, type = 4)))
  expect_equal(s$sel_q975[s$mean == 1.5],
               unname(stats::quantile(c(1, 2), 0.975, type = 4)))
  expect_equal(s$sel_q975[s$mean == 15],
               unname(stats::quantile(c(10, 20), 0.975, type = 4)))
})
