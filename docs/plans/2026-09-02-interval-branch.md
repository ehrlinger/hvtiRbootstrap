# Interval branch implementation plan - `boot_predict_ci()`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the interval branch — `boot_predict_ci()` — as the R port of
`%BNMNR` / `%BNPREV`, alongside the existing selection branch, sharing one
internal resampler and nothing else.

**Architecture:** `.boot_resample()` extracts the valid-model loop that
`%bootreg` and `%BNMNR` share; `boot_select()` is refactored onto it with no
behaviour change. `boot_predict_ci()` then adds a `statistic` callback (the
fitter contract minus the selection semantics), optional unit resampling with
renumbering, and a five-column percentile table whose coverage lives in the
column names.

**Tech Stack:** R package, roxygen2 with markdown enabled, testthat edition 3,
`devtools`. No new dependencies.

**Spec:** `dev/specs/2026-09-02-interval-branch-design.md`

## Global Constraints

- **`statistic` returns a named numeric vector, or `NULL`.** There is no `NA`
  semantics on this branch. `NA` on the *selection* branch means "this
  replicate did not choose this term" and is load-bearing; here nothing is
  chosen, so a missing estimate is a broken replicate. A returned vector
  containing any `NA` or non-finite value is treated as `NULL`.
- **Do not reuse `.bag_summary()`.** It counts non-missing values down a column,
  which is the selection branch's vote count and is meaningless here.
- **Quantile type is `4`** (SAS `PCTLDEF=1`). Never R's `type = 7` default.
- **No coverage argument anywhere in the package.** The five columns are
  `cll_p95`, `cll_p68`, `median`, `clu_p68`, `clu_p95`, in that order.
- **A new export fails the pkgdown gate until it is in `_pkgdown.yml`.** Add it
  in the same change.
- **No version bump.** `DESCRIPTION` stays as it is; bullets go under the
  standing `# hvtiRbootstrap (unreleased)` heading in `NEWS.md`.
- **80-character line limit**, and `lintr::lint_package()` must report **zero**
  lints — `lint.yaml` sets `LINTR_ERROR_ON_LINT: true`. Watch indentation when
  wrapping: two commits on the previous branch failed on `indentation_linter`.
- **ASCII only** in R source string literals.
- **Roxygen markdown is enabled.**
- Done for the whole plan: `devtools::test()` passes, `lintr::lint_package()` is
  0, and `devtools::check()` is 0 errors / 0 warnings / 0 notes from a clean
  `git archive` export.

**Environment gotcha:** `lintr::lint_package()`'s `object_usage_linter` resolves
symbols against the **installed** package copy. A stale library produces
spurious "no visible global function definition" warnings for new internals.
Run `R CMD INSTALL . --no-docs --no-byte-compile` and re-lint. That warning is
never fixed by editing code.

## File structure

| file | responsibility | change |
|---|---|---|
| `R/boot-resample.R` | the shared valid-model loop | **new** — `.boot_resample()` |
| `R/boot-select.R` | `%bootreg` port | refactor its loop onto `.boot_resample()`, no behaviour change |
| `R/boot-intervals.R` | `%BNMNR` port | **new** — `boot_predict_ci()`, `.interval_table()`, `.draw_units()` |
| `R/boot-intervals-class.R` | the returned object | **new** — `new_boot_intervals()`, `print`, `summary` |
| `tests/testthat/test-boot-resample.R` | | **new** |
| `tests/testthat/test-boot-intervals.R` | | **new** |
| `_pkgdown.yml` | | new reference section for the branch |
| `README.md`, `AGENTS.md`, `NEWS.md` | | the interval branch is now built |

`.interval_table()` and `.draw_units()` live beside `boot_predict_ci()` rather
than in their own files: they exist only for it, and the files that change
together live together. The class gets its own file because `boot_selection`'s
does (`R/boot-class.R`), and matching that is cheaper than justifying not to.

---

### Task 1: `.boot_resample()`, and `boot_select()` refactored onto it

**Files:**
- Create: `R/boot-resample.R`
- Modify: `R/boot-select.R:142-155` (the `while (kept < n_rep)` loop)
- Test: `tests/testthat/test-boot-resample.R` (new)

**Interfaces:**
- Produces: `.boot_resample(draw, fit, n_rep, max_attempts, caller, noun, hint)`
  — internal, not exported. `draw()` takes no arguments and returns one
  resampled object. `fit(d)` takes that object and returns a result or `NULL`.
  Returns `list(results = <list of length n_rep>, n_attempts = <integer>)`.
  Task 3 calls it.

**The constraint that shapes the signature.** `tests/testthat/test-boot-select.R:93`
asserts this exact text:

```
gave up after 25 attempts with 0 valid models of 10 requested
```

so the shared loop must reproduce `boot_select()`'s message verbatim, while
`boot_predict_ci()` needs its own wording. Hence `caller`, `noun` and `hint`
rather than a hardcoded string.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-boot-resample.R`:

```r
test_that(".boot_resample keeps n_rep results and counts every attempt", {
  # The %DO %WHILE(&SAMPLE<&RESAMPL) loop: a failed draw is redrawn in place
  # and does not consume one of the n_rep, so n_rep counts VALID results while
  # n_attempts counts draws. Both macros report both.
  i <- 0L
  draw <- function() {
    i <<- i + 1L
    i
  }
  # Every third draw fails.
  fit <- function(d) if (d %% 3L == 0L) NULL else d

  r <- .boot_resample(draw, fit, n_rep = 4L, max_attempts = 100L,
                      caller = "x", noun = "results", hint = "")

  expect_length(r$results, 4L)
  expect_equal(unlist(r$results), c(1, 2, 4, 5))
  # Draws 1, 2, 3 (fails), 4, 5 -- four kept in five attempts.
  expect_equal(r$n_attempts, 5L)
})

test_that(".boot_resample stops at max_attempts and says what it managed", {
  # Ours, not the macro's: %bootreg's loop advances only on success, so a model
  # that fails on every replicate never terminates. Survivable in a batch job
  # with an operator watching the log; an undiagnosable hang under R CMD check.
  expect_error(
    .boot_resample(function() 1, function(d) NULL, n_rep = 10L,
                   max_attempts = 25L, caller = "boot_select",
                   noun = "models", hint = "Check the data."),
    "gave up after 25 attempts with 0 valid models of 10 requested"
  )
})

test_that(".boot_resample's message carries the caller's own wording", {
  # boot_select() says "models"; the interval branch says "replicates". A
  # shared loop with one hardcoded noun would make one of them wrong.
  expect_error(
    .boot_resample(function() 1, function(d) NULL, n_rep = 2L,
                   max_attempts = 3L, caller = "boot_predict_ci",
                   noun = "replicates", hint = "Check the statistic."),
    "`boot_predict_ci\\(\\)` gave up after 3 attempts with 0 valid replicates"
  )
})

test_that(".boot_resample with max_attempts = Inf does not cap", {
  # The documented way back to the macro's uncapped behaviour.
  i <- 0L
  fit <- function(d) {
    i <<- i + 1L
    if (i < 50L) NULL else i
  }
  r <- .boot_resample(function() 1, fit, n_rep = 1L, max_attempts = Inf,
                      caller = "x", noun = "results", hint = "")

  expect_length(r$results, 1L)
  expect_equal(r$n_attempts, 50L)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-resample")'`

Expected: FAIL with `could not find function ".boot_resample"`.

- [ ] **Step 3: Write `.boot_resample()`**

Create `R/boot-resample.R`:

```r
# The valid-model loop, shared by both branches.
#
# WHY IT IS SHARED. %bootreg and %BNMNR are different macros doing different
# jobs -- one selects variables, one bands an estimate -- but their resampling
# loops are the same loop: draw, fit, keep on success, and on failure redraw in
# place WITHOUT counting the attempt, so RESAMPL= counts valid results rather
# than draws. Writing it twice would let the two copies drift, and the drift
# would be invisible because each branch's tests would still pass.
#
# WHY caller/noun/hint RATHER THAN ONE MESSAGE. boot_select() gave up "with 0
# valid models"; the interval branch gives up with 0 valid replicates. A test
# pins boot_select()'s wording, and a hardcoded noun would make one caller's
# error describe the other's job.
#
# The attempt budget is D3, ours rather than the macro's: %bootreg's loop
# advances only on a successful fit, so a model that fails on every replicate
# never terminates. `Inf` restores that.
.boot_resample <- function(draw, fit, n_rep, max_attempts, caller, noun,
                           hint) {
  kept <- vector("list", n_rep)
  n_kept <- 0L
  attempts <- 0L
  while (n_kept < n_rep) {
    if (attempts >= max_attempts) {
      stop("`", caller, "()` gave up after ", attempts, " attempts with ",
           n_kept, " valid ", noun, " of ", n_rep, " requested. ", hint,
           call. = FALSE)
    }
    attempts <- attempts + 1L
    r <- fit(draw())
    if (is.null(r)) next
    n_kept <- n_kept + 1L
    kept[[n_kept]] <- r
  }
  list(results = kept, n_attempts = attempts)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-resample")'`

Expected: PASS, 4 tests.

- [ ] **Step 5: Refactor `boot_select()` onto it**

In `R/boot-select.R`, replace this block:

```r
  fits <- vector("list", n_rep)
  kept <- 0L
  attempts <- 0L
  .t0 <- proc.time()[["elapsed"]]
```

...through the end of the `while` loop...

```r
  while (kept < n_rep) {
    if (attempts >= max_attempts)
      stop("`boot_select()` gave up after ", attempts, " attempts with ",
           kept, " valid models of ", n_rep, " requested. The model could not ",
           "be fitted on most replicates; check the formula and the data, or ",
           "raise `max_attempts`.", call. = FALSE)
    attempts <- attempts + 1L
    idx <- sample.int(n, size = draw, replace = TRUE)
    cf <- fitter(data[idx, , drop = FALSE], formula, ctrl)
    if (is.null(cf)) next
    kept <- kept + 1L
    fits[[kept]] <- cf
  }
```

with this:

```r
  .t0 <- proc.time()[["elapsed"]]
  # The loop moved to .boot_resample(), which %BNMNR shares. The comments that
  # were here -- why a failed fit is redrawn without counting, and why the
  # attempt budget is ours rather than the macro's -- live there now.
  drawn <- .boot_resample(
    draw = function() data[sample.int(n, size = draw, replace = TRUE), ,
                           drop = FALSE],
    fit  = function(d) fitter(d, formula, ctrl),
    n_rep = n_rep, max_attempts = max_attempts,
    caller = "boot_select", noun = "models",
    hint = paste0("The model could not be fitted on most replicates; check ",
                  "the formula and the data, or raise `max_attempts`.")
  )
  fits <- drawn$results
  attempts <- drawn$n_attempts
```

The local variable `draw` currently holds the row count (`draw <- max(1L,
round(n * fraction))`) and is used inside the closure above. That is fine —
the closure reads it — but **read the surrounding function before editing** and
confirm nothing else in `boot_select()` referred to `kept` after the loop. If it
did, use `n_rep` there: the loop cannot exit with `kept != n_rep`.

- [ ] **Step 6: Confirm `boot_select()` is unchanged in behaviour**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-select")'`

Expected: PASS, with **no test edited**. `boot_select()`'s existing tests are
the entire check on this refactor — in particular
`tests/testthat/test-boot-select.R:93`, which asserts the give-up message
verbatim, and the `max_attempts = Inf` test.

Then run the whole suite: `Rscript -e 'devtools::test()'` — must be 0 failures.

If any `boot_select()` test fails, the refactor changed behaviour. Fix the
refactor, never the test.

- [ ] **Step 7: Commit**

```bash
git add R/boot-resample.R R/boot-select.R tests/testthat/test-boot-resample.R
git commit -m "refactor: extract the valid-model loop both macros share

%bootreg and %BNMNR do different jobs but resample identically: draw, fit,
keep on success, redraw on failure without counting the attempt. The
interval branch needs the same loop, and two copies would drift invisibly.

boot_select()'s behaviour is unchanged; its existing tests are the check.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `.interval_table()`, the five named columns

**Files:**
- Create: `R/boot-intervals.R` (this task adds only `.interval_table()`)
- Test: `tests/testthat/test-boot-intervals.R` (new)

**Interfaces:**
- Produces: `.interval_table(m)` — internal. Takes a numeric matrix, one row per
  valid replicate, one column per named quantity, **no `NA`**. Returns a data
  frame with columns `parameter`, `cll_p95`, `cll_p68`, `median`, `clu_p68`,
  `clu_p95`, one row per column of `m`, in `colnames(m)` order,
  `row.names = NULL`. Task 3 calls it.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-boot-intervals.R`:

```r
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-intervals")'`

Expected: FAIL with `could not find function ".interval_table"`.

- [ ] **Step 3: Write `.interval_table()`**

Create `R/boot-intervals.R` beginning with this. (Task 3 appends
`boot_predict_ci()` and `.draw_units()` to the same file.)

```r
# The percentile points every bn.* macro asks PROC STDIZE for, and the names it
# gives them. 16 and 84 are the 68% interval -- plus or minus one standard
# error, to two figures -- and 2.5/97.5 the 95%.
#
# COVERAGE LIVES IN THE COLUMN NAME. Not one macro in the family takes a
# coverage level: they hardcode PCTLPTS and return both bands, distinguished by
# name. That is stronger than a `conf` argument, because a renderer selects a
# column rather than reading a field it might forget, and a function that takes
# no level cannot be handed 95 where it wanted 0.95.
#
# `median` is named for what it is. %BNMNR calls it MN_RES, which reads as a
# mean; it is PCTLPTS=50. The misnomer is not inherited.
.CI_POINTS <- c(cll_p95 = 0.025, cll_p68 = 0.16, median = 0.50,
                clu_p68 = 0.84, clu_p95 = 0.975)

# One row per quantity, percentiles taken down the replicates.
#
# THE BAND IS POINTWISE. Each column is summarised independently, which is what
# %BNMNR does -- transpose, one PROC STDIZE, transpose back. It is not a
# simultaneous band for a curve drawn through the columns, and the roxygen on
# boot_predict_ci() says so.
#
# type = 4 is SAS PCTLDEF=1, the weighted average at x_(np). R's default is
# type 7 and disagrees: on 1..100 it puts P2.5 at 3.475 rather than 2.5.
.interval_table <- function(m) {
  if (!is.matrix(m) || !is.numeric(m)) {
    stop("`m` must be a numeric matrix of replicate estimates.", call. = FALSE)
  }
  if (is.null(colnames(m))) {
    stop("`m` must have column names, one per estimated quantity.",
         call. = FALSE)
  }
  if (anyNA(m)) {
    stop("`m` has missing estimates. On this branch a replicate either ",
         "estimates every quantity or is discarded, so a missing value here ",
         "would narrow a band rather than record a choice.", call. = FALSE)
  }

  # unname() because quantile() labels its result "2.5%", "16%", ... and
  # vapply compares names against FUN.VALUE.
  q <- vapply(seq_len(ncol(m)),
              function(j) unname(stats::quantile(m[, j], .CI_POINTS,
                                                 type = 4)),
              numeric(length(.CI_POINTS)))
  out <- data.frame(parameter = colnames(m), stringsAsFactors = FALSE)
  for (i in seq_along(.CI_POINTS)) {
    out[[names(.CI_POINTS)[i]]] <- unname(q[i, ])
  }
  rownames(out) <- NULL
  out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-intervals")'`

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add R/boot-intervals.R tests/testthat/test-boot-intervals.R
git commit -m "feat: add .interval_table(), bn's five percentiles

PCTLPTS=2.5 16 50 84 97.5 with bn's own column names lowercased. Coverage
travels in the name because no macro in the family takes a level, and a
function that takes none cannot mislabel one. type = 4 is PCTLDEF=1.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: `boot_predict_ci()` with row resampling, and the `boot_intervals` class

**Files:**
- Modify: `R/boot-intervals.R` (append `boot_predict_ci()`)
- Create: `R/boot-intervals-class.R`
- Test: `tests/testthat/test-boot-intervals.R` (append)

**Interfaces:**
- Consumes: `.boot_resample()` from Task 1, `.interval_table()` from Task 2.
- Produces: `boot_predict_ci(data, statistic, n_rep = 1000, fraction = 1,
  id = NULL, max_attempts = 10 * n_rep, seed = NULL, ...)`, **exported**,
  returning an object of class `boot_intervals` with fields `estimates`
  (matrix), `intervals` (the Task 2 data frame), `n_rep`, `n_attempts`, `call`,
  `control`. Task 4 adds the `id` behaviour; **this task accepts the argument
  and errors if it is not `NULL`**, so the signature is stable from here.
- Produces: `new_boot_intervals()`, `print.boot_intervals()`,
  `summary.boot_intervals()`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-boot-intervals.R`:

```r
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
  # No coverage argument exists anywhere in this package, by design.
  expect_error(boot_predict_ci(df, fx_statistic, n_rep = 5, conf = 0.95),
               "unused argument|conf")
})

test_that("boot_intervals prints its counts and summarises to the bands", {
  df <- data.frame(x = 1:50)
  r <- boot_predict_ci(df, fx_statistic, n_rep = 20, seed = 1)

  expect_output(print(r), "boot_intervals")
  expect_output(print(r), "20")
  expect_equal(summary(r), r$intervals)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-intervals")'`

Expected: FAIL with `could not find function "boot_predict_ci"`.

- [ ] **Step 3: Write the class**

Create `R/boot-intervals-class.R`:

```r
# The interval branch's object. Deliberately shares nothing with
# boot_selection: that class's coefficients matrix carries NA to mean "not
# selected", and reusing it here would invite a reader to run boot_summary()
# over estimates where missingness has no such meaning.
new_boot_intervals <- function(estimates, intervals, n_rep, n_attempts, call,
                               control = NULL) {
  structure(
    list(estimates = estimates, intervals = intervals, n_rep = n_rep,
         n_attempts = n_attempts, call = call, control = control),
    class = "boot_intervals"
  )
}

#' @export
print.boot_intervals <- function(x, ...) {
  cat("<boot_intervals>\n")
  cat("  replicates: ", x$n_rep, " valid of ", x$n_attempts, " attempts\n",
      sep = "")
  cat("  quantities: ", ncol(x$estimates), "\n", sep = "")
  cat("Bands are POINTWISE 95% and 68% percentile intervals.\n")
  cat("Use summary() for the per-quantity table.\n")
  invisible(x)
}

#' @export
summary.boot_intervals <- function(object, ...) object$intervals
```

- [ ] **Step 4: Write `boot_predict_ci()`**

Append to `R/boot-intervals.R`. Write the roxygen to the house contract: name
the macro it ports and the parameter it replaces, and mark every divergence
**Divergence**. The reader is a CORR biostatistician who already runs `%BNMNR`.

```r
#' Band an estimate by bootstrap resampling
#'
#' The R port of `%BNMNR` and `%BNPREV` (`bn.*` in the CORR macro library).
#' Resamples `data`, computes `statistic` on each replicate, and reports the
#' percentile intervals of each estimated quantity.
#'
#' This is the **interval** branch. It is not variable selection: nothing is
#' chosen, the replicates are a distribution rather than a vote, and there is
#' no `NA` semantics. For selection, see [boot_select()].
#'
#' `statistic` is the fitter contract with the selection semantics removed. It
#' takes one resampled frame and returns a **named numeric vector** of that
#' replicate's estimates, or `NULL` when the replicate did not fit. The names
#' are the quantities banded, so a caller wanting a curve evaluates it on their
#' own grid inside `statistic` and names the elements -- which is what the macro
#' does too, in a `PROC NLMIXED` block the analyst edits.
#'
#' **The bands are pointwise.** Each quantity is summarised independently, as
#' `%BNMNR` does. A curve drawn through `cll_p95` is the 2.5th percentile at
#' each point, not a 95% region for the curve.
#'
#' No argument sets a coverage level, here or anywhere in this package. The
#' macros do not take one either: they hardcode
#' `PCTLPTS=2.5 16 50 84 97.5` and return both bands in columns named for their
#' coverage. Percentiles use [stats::quantile()] `type = 4`, which is SAS's
#' `PCTLDEF=1`.
#'
#' @param data A data frame.
#' @param statistic Function of `(data, ...)` returning a named numeric vector
#'   of one replicate's estimates, or `NULL` if the replicate failed.
#'   `%BNMNR` equivalent: the `PROC NLMIXED` block.
#' @param n_rep Number of **valid** replicates (`%BNMNR` `RESAMPL=`).
#'   **Divergence:** the macro defaults to 100; this defaults to 1000, matching
#'   [boot_select()] in this package. A hundred replicates puts the 2.5th
#'   percentile on the third order statistic, where it is visibly unstable.
#'   Pass `n_rep = 100` to reproduce the macro.
#' @param fraction Fraction of units drawn per replicate (`%BNMNR`
#'   `FRACTION=`). Applied, as the macro applies it -- unlike `%bootreg`, which
#'   computes it and then draws the full size anyway.
#' @param id Column naming the resampling unit, or `NULL` to draw rows. When
#'   given, units are drawn with replacement and **renumbered**, so a unit drawn
#'   twice becomes two distinct units; the new id is in a `.boot_unit` column.
#'   `%BNMNR` equivalent: the patient-level `INDAT=` joined to the repeated
#'   `INMULT=`.
#' @param max_attempts Budget of draws before giving up. **Divergence:**
#'   `%BNMNR` has no cap and never terminates when every replicate fails. Pass
#'   `Inf` to restore that.
#' @param seed Optional integer for reproducibility (`%BNMNR` `SEED=`).
#' @param ... Passed to `statistic`.
#' @return An object of class `boot_intervals`. `$estimates` is a matrix with
#'   one row per valid replicate and one column per quantity; `$intervals` is
#'   the per-quantity table with columns `parameter`, `cll_p95`, `cll_p68`,
#'   `median`, `clu_p68`, `clu_p95`. `$control` records the run's settings.
#' @seealso [boot_select()] for the selection branch.
#' @examples
#' # The names of the returned vector are the quantities banded. Here, two
#' # summaries of the same column; in a real screen they are typically a
#' # fitted curve evaluated on a grid.
#' df <- data.frame(x = rnorm(200))
#' est <- function(d, ...) c(mean = mean(d$x), sd = sd(d$x))
#'
#' r <- boot_predict_ci(df, est, n_rep = 100, seed = 42)
#' r
#' summary(r)
#' @export
boot_predict_ci <- function(data, statistic, n_rep = 1000, fraction = 1,
                            id = NULL, max_attempts = 10 * n_rep,
                            seed = NULL, ...) {
  # Restore the caller's stream FIRST, before any argument promise is forced,
  # for the reason boot_select() documents at length: `data` is often an
  # expression that itself draws.
  if (!is.null(seed)) withr::local_preserve_seed()
  if (!is.data.frame(data) || nrow(data) == 0L) {
    stop("`data` must be a data frame with at least one row.", call. = FALSE)
  }
  if (!is.function(statistic)) {
    stop("`statistic` must be a function of (data, ...) returning a named ",
         "numeric vector, or NULL.", call. = FALSE)
  }
  if (!is.numeric(fraction) || length(fraction) != 1L || is.na(fraction) ||
        fraction <= 0 || fraction > 1) {
    stop("`fraction` must be greater than 0 and at most 1.", call. = FALSE)
  }
  if (!is.numeric(n_rep) || length(n_rep) != 1L || is.na(n_rep) ||
        n_rep < 1 || n_rep != trunc(n_rep) || is.infinite(n_rep)) {
    stop("`n_rep` must be a positive whole number of replicates.",
         call. = FALSE)
  }
  if (!is.numeric(max_attempts) || length(max_attempts) != 1L ||
        is.na(max_attempts) || max_attempts < n_rep ||
        (is.finite(max_attempts) && max_attempts != trunc(max_attempts))) {
    stop("`max_attempts` must be a whole number at least as large as ",
         "`n_rep`, or `Inf`.", call. = FALSE)
  }
  if (!is.null(id)) {
    stop("`id` is not implemented yet.", call. = FALSE)
  }
  if (!is.null(seed)) set.seed(seed)

  n <- nrow(data)
  n_draw <- max(1L, round(n * fraction))
  .t0 <- proc.time()[["elapsed"]]

  # The first valid replicate fixes the names. A later one disagreeing is
  # discarded like any other failure -- %BNMNR's &_ON=&_BN check, made stricter
  # because a matching COUNT with different names would assemble one row of the
  # percentile table out of two different quantities.
  names_seen <- NULL
  one <- function(d) {
    v <- statistic(d, ...)
    if (is.null(v)) return(NULL)
    if (!is.numeric(v) || is.null(names(v)) || anyNA(v) || !all(is.finite(v))) {
      return(NULL)
    }
    if (is.null(names_seen)) {
      names_seen <<- names(v)
    } else if (!identical(names(v), names_seen)) {
      return(NULL)
    }
    v
  }

  drawn <- .boot_resample(
    draw = function() data[sample.int(n, size = n_draw, replace = TRUE), ,
                           drop = FALSE],
    fit = one, n_rep = n_rep, max_attempts = max_attempts,
    caller = "boot_predict_ci", noun = "replicates",
    hint = paste0("`statistic` returned NULL, a non-finite value, or a ",
                  "different set of names on most replicates.")
  )

  m <- do.call(rbind, drawn$results)
  rownames(m) <- NULL

  control <- list(
    fraction = fraction, id = if (is.null(id)) NA_character_ else id,
    seed = if (is.null(seed)) NA_real_ else as.numeric(seed),
    n_rows = as.integer(n), n_units = as.integer(n),
    n_names = ncol(m),
    elapsed_mins = (proc.time()[["elapsed"]] - .t0) / 60,
    package = as.character(utils::packageVersion("hvtiRbootstrap"))
  )

  new_boot_intervals(m, .interval_table(m), n_rep = as.integer(n_rep),
                     n_attempts = drawn$n_attempts, call = match.call(),
                     control = control)
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-intervals")'`

Expected: PASS. If the `conf = 0.95` guard test fails, that is because `...`
swallows it and passes it to `statistic` — which is correct R behaviour and
means the test's `"unused argument|conf"` alternative did not match. In that
case the statistic errors on the unexpected argument; adjust the test to assert
the error it actually raises, and **do not** add a `conf` argument.

- [ ] **Step 6: Document and register the export**

Run: `Rscript -e 'devtools::document()'`

Confirm `NAMESPACE` now exports `boot_predict_ci` and registers the two S3
methods.

Then add it to `_pkgdown.yml`. The pkgdown gate fails on an export missing from
the reference index. Insert this section immediately **after** the
`"5. Fitters"` section and before `"Package overview"`:

```yaml
- title: "6. Band an estimate — `%BNMNR` and `%BNPREV`"
  desc: >
    The other branch. Everything above selects variables: refit on each
    replicate, count which terms survived, and a term the model did not choose
    is left missing. This does not select anything — it resamples to put a
    band around an estimate, so the replicates are a distribution rather than
    a vote and there is no missingness to read. `statistic` is the `fitter`
    contract with the selection semantics removed. No argument sets a
    coverage level, because no macro in the family takes one: both the 95% and
    the 68% band come back, in columns named for their coverage.
  contents:
  - boot_predict_ci
```

- [ ] **Step 7: Run the whole suite and lint**

Run: `Rscript -e 'devtools::test()'` — 0 failures.

Run: `Rscript -e 'l <- lintr::lint_package(); cat("TOTAL LINTS:", length(l), "\n"); print(l)'` — must be 0. Re-install first if you see `object_usage_linter` warnings.

- [ ] **Step 8: Commit**

```bash
git add R/boot-intervals.R R/boot-intervals-class.R NAMESPACE man/ _pkgdown.yml tests/testthat/test-boot-intervals.R
git commit -m "feat: add boot_predict_ci(), the interval branch

The R port of %BNMNR/%BNPREV. statistic() is the fitter contract minus the
selection semantics: a named numeric vector, or NULL. The names are the
quantities banded, so the grid is the statistic's business, as it is the
macro-editor's today.

No coverage argument. Both the 95% and 68% bands come back in columns named
for their coverage, as every bn.* macro returns them.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: unit resampling via `id`, with renumbering

**Files:**
- Modify: `R/boot-intervals.R` — add `.draw_units()`, replace the `id` guard
- Test: `tests/testthat/test-boot-intervals.R` (append)

**Interfaces:**
- Consumes: `boot_predict_ci()`'s signature from Task 3, unchanged.
- Produces: `.draw_units(data, id, n_units)` — internal. Returns one resampled
  frame with a `.boot_unit` integer column.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-boot-intervals.R`:

```r
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
  seen <- function(dd, ...) c(units = length(unique(dd$.boot_unit)),
                              rows = nrow(dd))

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

test_that("the control record names the resampling unit", {
  d <- data.frame(pt = rep(1:4, each = 2), x = 1)
  est <- function(dd, ...) c(m = mean(dd$x))

  r <- boot_predict_ci(d, est, n_rep = 5, id = "pt", seed = 1)

  expect_equal(r$control$id, "pt")
  expect_equal(r$control$n_units, 4L)
  expect_equal(r$control$n_rows, 8L)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-intervals")'`

Expected: FAIL — `id` is not implemented yet.

- [ ] **Step 3: Write `.draw_units()`**

Add to `R/boot-intervals.R`, before `boot_predict_ci()`:

```r
# Draw whole units with replacement, and renumber them.
#
# WHY RENUMBER. %BNMNR sets _PTID=_COUNTER as it draws, BEFORE joining the
# repeated records, and then fits random u ~ normal(0, ...) subject=_PTID. A
# patient drawn twice therefore enters the model as two patients. Reusing the
# original id instead would give the two copies one shared random effect, which
# understates between-unit variance -- the quantity the bootstrap is there to
# estimate. The renumbering is the method, not bookkeeping.
#
# The new id goes in `.boot_unit` so a statistic can group on it. A data frame
# that already has that column is refused rather than overwritten: the caller's
# statistic would otherwise read a column that no longer means what they wrote.
.draw_units <- function(data, id, n_units) {
  units <- unique(data[[id]])
  drawn <- sample(units, size = n_units, replace = TRUE)
  rows <- lapply(seq_along(drawn), function(k) {
    d <- data[data[[id]] == drawn[[k]], , drop = FALSE]
    d[[".boot_unit"]] <- k
    d
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
```

- [ ] **Step 4: Wire it into `boot_predict_ci()`**

Replace this guard:

```r
  if (!is.null(id)) {
    stop("`id` is not implemented yet.", call. = FALSE)
  }
```

with:

```r
  if (!is.null(id)) {
    if (!is.character(id) || length(id) != 1L || !id %in% names(data)) {
      stop("`id` must name a single column of `data`; `",
           paste(format(id), collapse = ", "), "` is not a column.",
           call. = FALSE)
    }
    if (".boot_unit" %in% names(data)) {
      stop("`data` already has a `.boot_unit` column, which is the name this ",
           "function gives the redrawn unit. Rename it: overwriting it would ",
           "change what `statistic` reads.", call. = FALSE)
    }
  }
```

Then replace the `n` / `n_draw` / `draw` assignments so units are the sampling
frame when `id` is given:

```r
  n <- nrow(data)
  n_units <- if (is.null(id)) n else length(unique(data[[id]]))
  n_draw <- max(1L, round(n_units * fraction))
  draw_one <- if (is.null(id)) {
    function() data[sample.int(n, size = n_draw, replace = TRUE), ,
                    drop = FALSE]
  } else {
    function() .draw_units(data, id, n_draw)
  }
```

and pass `draw = draw_one` to `.boot_resample()`. In `control`, set
`n_units = as.integer(n_units)`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-intervals")'`

Expected: PASS, including every Task 3 test — the `id = NULL` path must be
unchanged.

- [ ] **Step 6: Whole suite, lint, commit**

Run: `Rscript -e 'devtools::test()'` and
`Rscript -e 'l <- lintr::lint_package(); cat("TOTAL LINTS:", length(l), "\n")'`.

```bash
git add R/boot-intervals.R tests/testthat/test-boot-intervals.R
git commit -m "feat: draw whole units, and renumber them

%BNMNR bootstraps patients and assigns _PTID=_COUNTER before joining their
repeated records, so a patient drawn twice enters the model as two
patients. Without the renumbering both copies share a random effect and the
resample understates between-unit variance -- the quantity the bootstrap
exists to estimate. The renumbering is the method, not bookkeeping.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Documentation, and the release gate

**Files:**
- Modify: `README.md`, `AGENTS.md`, `NEWS.md`
- Modify: `dev/specs/2026-09-02-interval-branch-design.md` (its checklist)

- [ ] **Step 1: Update `README.md`**

The README's "Two branches, one resampling loop" section currently ends by
saying the interval branch is specified and not yet built. Read it, then replace
that sentence so it describes what now ships, naming `boot_predict_ci()` and
keeping the section's existing voice. Do not restructure the section.

- [ ] **Step 2: Update `AGENTS.md`**

Its branch-split bullet says the interval branch "is specified ... and not
built". Read the bullet, then correct that clause to name `boot_predict_ci()`
and `R/boot-intervals.R`. Add one sentence to the same bullet:

```markdown
  A fitter returns `NA` for a term the model did not choose; a `statistic`
  never does, because nothing is being chosen -- a missing estimate there is a
  broken replicate and the whole replicate is discarded. Do not carry the `NA`
  rule across the branch line in either direction.
```

- [ ] **Step 3: Add the `NEWS.md` bullets**

Under the standing `# hvtiRbootstrap (unreleased)` heading, matching the
narrative voice of the bullets already there:

```markdown
* **The interval branch is built.** `boot_predict_ci()` is the R port of
  `%BNMNR` and `%BNPREV`: it resamples, computes a `statistic` on each
  replicate, and reports percentile bands. It is not variable selection --
  nothing is chosen, the replicates are a distribution rather than a vote, and
  there is no `NA` semantics. `statistic` is the fitter contract with the
  selection semantics removed: a named numeric vector, or `NULL` when the
  replicate failed. The names are the quantities banded, so a caller wanting a
  curve evaluates it on their own grid inside `statistic` -- which is what the
  macro does too, in a `PROC NLMIXED` block the analyst edits.
* **`id` draws whole units and renumbers them.** `%BNMNR` bootstraps patients
  and assigns `_PTID=_COUNTER` before joining their repeated records, so a
  patient drawn twice enters the model as two patients. Without that the two
  copies share a random effect and the resample understates between-unit
  variance. The redrawn unit is in a `.boot_unit` column.
* **No function in this package takes a coverage level.** `boot_predict_ci()`
  returns both the 95% and the 68% band in columns named for their coverage --
  `cll_p95`, `cll_p68`, `median`, `clu_p68`, `clu_p95` -- because that is what
  every `bn.*` macro returns, and a function that takes no level cannot be
  handed 95 where it wanted 0.95.
* The resampling loop `%bootreg` and `%BNMNR` share is now one internal rather
  than two copies. `boot_select()`'s behaviour is unchanged.
```

- [ ] **Step 4: Tick the spec's checklist**

In `dev/specs/2026-09-02-interval-branch-design.md`, tick the "Definition of
done" items that Tasks 1-4 delivered.

- [ ] **Step 5: Run the full release gate**

```
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test()'
Rscript -e 'l <- lintr::lint_package(); cat("TOTAL LINTS:", length(l), "\n"); print(l)'
```

Then `R CMD check` from a clean export, **not** the working tree:

```bash
D=$(mktemp -d) && mkdir -p "$D/pkg" && git archive HEAD | tar -x -C "$D/pkg"
cd "$D" && R CMD build pkg && R CMD check --no-manual hvtiRbootstrap_*.tar.gz
```

Expected: 0 errors, 0 warnings, 0 notes.

Also build the pkgdown site, since a missing reference entry fails that gate and
`R CMD check` will not catch it:

```bash
Rscript -e 'pkgdown::build_site(devel = FALSE, preview = FALSE)'
```

Expected: no error about a topic missing from the index.

- [ ] **Step 6: Commit and stop**

```bash
git add README.md AGENTS.md NEWS.md dev/specs/2026-09-02-interval-branch-design.md man/
git commit -m "docs: the interval branch is built

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Do **not** push and do **not** open a pull request; the controller handles that.

---

## What this plan does not do

- **No pooling of chunked interval runs.** The selection branch has it because a
  screen over 160 candidates ran 22 minutes per phase; whether an interval run
  is comparably long depends entirely on the caller's `statistic`, so there is
  no evidence either way yet.
- **No `bl_ord` convenience wrapper.** Those macros return the 95% pair and the
  median; they get the same five columns and ignore two. A second output shape
  would have to be told apart at every call site.
- **No quantile fitter** (`bq`, hvtiRbootstrap#16), **no hazard fitter**, **no
  penalised selection.** Each is still its own change.
- **No version bump.** Bump when you tag, not when you merge.
