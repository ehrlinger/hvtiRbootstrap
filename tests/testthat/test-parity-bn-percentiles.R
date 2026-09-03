# Parity for the percentile step every bn.* macro ends with:
#
#   PROC STDIZE ... PCTLMTD=ORD_STAT PCTLDEF=1 PCTLPTS=2.5 16 50 84 97.5
#
# PCTLDEF=1 is the weighted average at x_(np), which is R's
# stats::quantile(type = 4) and NOT the type = 7 default. This is the interval
# branch's parity oracle: given a fixed matrix of replicate estimates, the
# interval arithmetic must reproduce SAS exactly.
#
# WHY THIS FIXTURE CAN EXIST AT ALL. Resampling cannot be parity-tested -- the
# two languages draw different samples -- but the percentile step is
# deterministic given the replicates. So the oracle is a table of numbers and
# the five percentiles SAS returns for it, which needs no cohort data.
#
# HOW TO REGENERATE. dev/sas/make-bn-fixture.R writes both halves from one
# source: the input CSV read below, and dev/sas/bn-percentile-fixture.sas.
# Run that .sas on a machine with SAS and commit the CSV it writes.

fixture_path <- function(f) testthat::test_path("fixtures", f)

test_that("the fixture input is present and has the shape the oracle needs", {
  # Checked separately from the parity test below so that a missing or damaged
  # INPUT is a failure, while a missing SAS OUTPUT is only a skip. The input is
  # ours, is committed, and ships in the tarball; the output has to come off a
  # SAS machine.
  #
  # A HARD FAILURE, NOT A SKIP. This file is in the repository and in the built
  # package, so its absence is never "not captured yet" -- it is a deletion, a
  # broken path, or an .Rbuildignore rule that started excluding it. Skipping
  # would let all three through in green CI, and the parity test below would
  # then skip too, so the whole oracle could vanish without a single failure.
  expect_true(file.exists(fixture_path("bn-percentile-input.csv")),
              info = "bn-percentile-input.csv is committed and must ship")
  d <- utils::read.csv(fixture_path("bn-percentile-input.csv"),
                       stringsAsFactors = FALSE)

  expect_setequal(names(d), c("dataset", "column", "replicate", "estimate"))
  expect_true(nrow(d) > 0L)
  expect_false(anyNA(d$estimate))
  # One estimate per (dataset, column, replicate), or the pivot below would
  # silently drop rows and compare a different table than SAS saw.
  expect_false(anyDuplicated(d[c("dataset", "column", "replicate")]) > 0L)
})

# SAS writes PROC STDIZE's OUTSTAT whole, so the percentile rows arrive labelled
# in _TYPE_ rather than at fixed column positions. Position depends on how many
# points were requested; reading the label does not.
.pctl_of_type <- function(type) {
  as.numeric(sub("_", ".", sub("^[Pp]", "", trimws(type)), fixed = TRUE))
}

test_that("quantile(type = 4) reproduces PROC STDIZE PCTLDEF=1", {
  expected <- fixture_path("bn-percentile-expected.csv")
  skip_if_not(
    file.exists(expected),
    paste0("bn-percentile-expected.csv is not committed yet. Run ",
           "dev/sas/bn-percentile-fixture.sas on a machine with SAS and ",
           "commit the CSV it writes into tests/testthat/fixtures/.")
  )

  input <- utils::read.csv(fixture_path("bn-percentile-input.csv"),
                           stringsAsFactors = FALSE)
  got <- utils::read.csv(expected, stringsAsFactors = FALSE,
                         check.names = FALSE)
  names(got) <- tolower(names(got))
  expect_true(all(c("dataset", "_type_") %in% names(got)))

  rows <- got[!is.na(.pctl_of_type(got[["_type_"]])), , drop = FALSE]
  expect_gt(nrow(rows), 0L)

  checked <- 0L
  for (i in seq_len(nrow(rows))) {
    p <- .pctl_of_type(rows[[i, "_type_"]]) / 100
    ds <- trimws(rows[[i, "dataset"]])
    for (cl in setdiff(names(rows), c("dataset", "_type_"))) {
      sas <- suppressWarnings(as.numeric(rows[[i, cl]]))
      # A column absent from this dataset is missing in the stacked OUTSTAT.
      # That is the stacking, not a disagreement.
      if (is.na(sas)) next
      v <- input$estimate[input$dataset == ds & input$column == cl]
      if (!length(v)) next
      r <- unname(stats::quantile(v, p, type = 4))
      expect_equal(r, sas, tolerance = 1e-8,
                   label = paste0(ds, "$", cl, " at P", p * 100))
      checked <- checked + 1L
    }
  }
  # A loop that matched nothing would pass in silence, and this whole file
  # exists to make a claim about SAS. Assert that it actually compared.
  expect_gt(checked, 0L)
})

test_that("the type = 7 default would NOT reproduce SAS", {
  # The point of the fixture. If R's default happened to agree, the parity
  # test above would pass while asserting nothing about PCTLDEF=1, and a later
  # simplification to quantile(v, p) would go unnoticed.
  #
  # Checked against the fixture INPUT rather than SAS output, so it runs
  # whether or not the SAS half has been captured yet: these are facts about
  # R's own quantile types, and they are what makes the oracle discriminating.
  # Hard, for the same reason as above: the input is committed, so a missing
  # one is a defect rather than a fixture not yet captured.
  expect_true(file.exists(fixture_path("bn-percentile-input.csv")))
  input <- utils::read.csv(fixture_path("bn-percentile-input.csv"),
                           stringsAsFactors = FALSE)
  p <- c(0.025, 0.16, 0.50, 0.84, 0.975)

  disagrees <- function(k) {
    q4 <- unname(stats::quantile(k$estimate, p, type = 4))
    q7 <- unname(stats::quantile(k$estimate, p, type = 7))
    !isTRUE(all.equal(q4, q7))
  }
  by_col <- split(input, list(input$dataset, input$column), drop = TRUE)
  differs <- vapply(by_col, disagrees, logical(1))

  # Not every column can discriminate: a constant column, a single
  # observation, and this tie pattern give the same answer under both
  # definitions. Those are invariants worth pinning, but they are not the
  # discriminating cases, so require that several columns genuinely differ.
  expect_gte(sum(differs), 4L)
  expect_true(differs[["n100.seq"]])
  expect_true(differs[["n4.small"]])
})

test_that("1..100 lands exactly on its own percentiles under type 4", {
  # The clearest statement of what PCTLDEF=1 does, and hand-checkable without
  # SAS: for the integers 1..100 the weighted average at x_(np) returns the
  # requested percentile itself. Type 7 returns 3.475 for P2.5.
  v <- 1:100

  expect_equal(unname(stats::quantile(v, c(.025, .16, .5, .84, .975),
                                      type = 4)),
               c(2.5, 16, 50, 84, 97.5))
  expect_equal(unname(stats::quantile(v, 0.025, type = 7)), 3.475)
})
