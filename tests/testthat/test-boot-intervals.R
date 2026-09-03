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
