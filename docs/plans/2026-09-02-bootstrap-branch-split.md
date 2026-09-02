# Bootstrap branch split - selection-side changes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the pooled summary's mislabelled interval columns, make
`boot_bag()` and `boot_pool_chunks()` build `$boot$summary` through one
constructor so they cannot disagree, and give `boot_validate()` a column check
so drift is caught.

**Architecture:** One new internal, `.bag_summary()`, wraps `boot_summary()` and
returns the bag-side summary: keyed `parameter` rather than `variable`, with two
selection-conditional quantile columns. `boot_bag()` and `boot_pool_chunks()`
both call it, so shape agreement is guaranteed by construction rather than
asserted by a test. `boot_pool_chunks()` loses its hand-rolled duplicate of the
summary arithmetic. `boot_summary()` itself is untouched.

**Tech Stack:** R package, roxygen2 with markdown enabled, testthat edition 3,
`devtools` for test/document/check. No new dependencies.

**Spec:** `dev/specs/2026-09-02-bootstrap-branches-design.md`

## Global Constraints

- **No new exports.** Every change is to existing exported behaviour or to an
  internal. `_pkgdown.yml` therefore needs no edit.
- **`NA` is the design.** A term a model did not select is `NA`. Never fill it
  with `0`. Every statistic here counts or ignores non-missing values down a
  column.
- **Quantile type is `4`**, which is SAS `PCTLDEF=1`. Never the `type = 7`
  default.
- **No version bump.** `DESCRIPTION` stays at `0.9.2`. Work lands as bullets
  under the standing `# hvtiRbootstrap (unreleased)` heading in `NEWS.md`. See
  "Spec refinement 2" below.
- **80-character line limit.** There is no `.lintr`, so lintr's defaults apply.
- **ASCII only** in R source string literals.
- **testthat edition 3**, test files named `test-*.R` with a hyphen.
- **Roxygen markdown is enabled** (`Roxygen: list(markdown = TRUE)`).
- **Never push to `main`.** Branch, then open a PR.
- Definition of done for the whole plan: `devtools::test()` passes and
  `devtools::check()` is 0 errors, 0 warnings, 0 notes.

## File structure

| file | responsibility | change |
|---|---|---|
| `R/boot-summary.R` | `%SUMBOOT` port, and now the bag-side summary built on it | add internal `.bag_summary()`; `boot_summary()` unchanged |
| `R/boot-bag.R` | turns a `boot_selection` into a bag | call `.bag_summary()` instead of `boot_summary()`; update `@return` |
| `R/boot-pool.R` | pools chunked runs | call `.bag_summary()`; delete the duplicated summary arithmetic and the two `ci_*` columns |
| `R/boot-validate.R` | the shape gate a report reads | add a `$boot$summary` column check |
| `tests/testthat/test-boot-summary.R` | | tests for `.bag_summary()` |
| `tests/testthat/test-boot-bag.R` | | tests that the bag carries the new shape |
| `tests/testthat/test-boot-pool.R` | | tests that pooled and bagged shapes agree |
| `tests/testthat/test-boot-validate.R` | | tests for the column check |
| `AGENTS.md`, `README.md` | | state the branch split |
| `NEWS.md` | | bullets under `(unreleased)` |

`.bag_summary()` lives in `R/boot-summary.R` rather than a new file because it
is `boot_summary()` plus a rename and two columns - the files that change
together live together.

## Two refinements the spec left open

Both are decisions the spec did not make. They are recorded here and the spec's
own checklist is corrected in Task 5.

**Refinement 1 - the validator checks three columns, not nine.**
`boot_validate()` requires `parameter`, `n` and `pct` on `$boot$summary`, not
the full nine. Requiring nine would reject every hand-built bag, including this
package's own `fx_bag()` fixture and the example in `boot_validate()`'s roxygen,
both of which carry exactly those three. `boot_validate()` exists to accept bags
written by runners - its error text says so - and the nine-column agreement
between the two constructors is guaranteed by their sharing `.bag_summary()`,
which is stronger than a check. The check's job is the defect that actually
shipped: a summary keyed `variable` where the reporting layer reads `parameter`.

**Refinement 2 - no version bump.** The spec's checklist says "patch bump". That
is wrong under the convention now in force. `AGENTS.md` says to bump when you
tag, not when you merge, and `tests/testthat/test-package.R` skips headings that
carry no version precisely so work can merge under a standing `(unreleased)`
heading. `DESCRIPTION` stays `0.9.2`.

---

### Task 1: `.bag_summary()`, the one summary constructor

**Files:**
- Modify: `R/boot-summary.R` (append after `boot_summary()`)
- Test: `tests/testthat/test-boot-summary.R` (append)

**Interfaces:**
- Consumes: `boot_summary(m)`, already in this file, which returns a data frame
  with columns `variable`, `n`, `pct`, `mean`, `sd`, `min`, `max` ordered by
  descending `n` then `variable`.
- Produces: `.bag_summary(m)` - internal, not exported. Takes a numeric matrix
  with one row per replicate, one column per term, `NA` where unselected.
  Returns a data frame with columns `parameter`, `n`, `pct`, `mean`, `sd`,
  `min`, `max`, `sel_q025`, `sel_q975`, in that order, `row.names = NULL`.
  Tasks 2 and 3 both call it.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-boot-summary.R`:

```r
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-summary")'`

Expected: FAIL, with `could not find function ".bag_summary"`.

- [ ] **Step 3: Write the implementation**

Append to `R/boot-summary.R`:

```r
# The bag-side summary: boot_summary() keyed the way a bag is keyed, plus the
# spread of each coefficient across the replicates that selected it.
#
# WHY ONE CONSTRUCTOR. boot_bag() and boot_pool_chunks() both fill
# `$boot$summary`, and before this they built it separately -- seven columns
# keyed `variable` from one, nine keyed `parameter` from the other. A renderer
# then saw a different shape depending on whether the run happened to be
# chunked. Nothing inside the package reads that slot, so nothing caught it.
# Sharing the constructor makes the shapes agree by construction.
#
# WHY `parameter` RATHER THAN `variable`. `$boot$replicates`, boot_health(),
# and boot_validate()'s own documented example all say `parameter`. Only
# boot_summary() says `variable`, and boot_summary() is the standalone %SUMBOOT
# port rather than a bag -- it keeps its own key.
#
# WHY THESE ARE NOT CALLED ci_lower/ci_upper. They are computed over the
# replicates in which the term was SELECTED, so for a term chosen half the time
# the interval is over half the replicates. That is not a confidence interval
# for the coefficient, and it is perverse in the direction that matters: the
# weaker the term, the narrower the interval looks. It is a sibling of the
# mean/sd/min/max above, which are conditional in exactly the same way and
# always have been. The name says selection, and deliberately does not resemble
# the interval branch's cll_p95/clu_p95.
#
# WHY type = 4. SAS PROC STDIZE runs PCTLDEF=1, which is the weighted average
# at x_(np) -- R's type 4, not the type 7 default.
.bag_summary <- function(m) {
  out <- boot_summary(m)
  names(out)[names(out) == "variable"] <- "parameter"

  # NA dropped per column rather than na.rm = TRUE, so that a column of
  # nothing yields NA instead of an error, matching boot_summary()'s own
  # handling of an undefined statistic.
  q <- function(col, p) {
    v <- col[!is.na(col)]
    if (length(v) == 0L) return(NA_real_)
    unname(stats::quantile(v, p, type = 4))
  }
  j <- match(out$parameter, colnames(m))
  out$sel_q025 <- vapply(j, function(k) q(m[, k], 0.025), numeric(1))
  out$sel_q975 <- vapply(j, function(k) q(m[, k], 0.975), numeric(1))

  rownames(out) <- NULL
  out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-summary")'`

Expected: PASS, all tests in the file, including the pre-existing
`boot_summary()` tests which must be unaffected.

- [ ] **Step 5: Commit**

```bash
git add R/boot-summary.R tests/testthat/test-boot-summary.R
git commit -m "feat: add .bag_summary(), the one bag-side summary constructor

boot_bag() and boot_pool_chunks() built \$boot\$summary separately, in two
shapes with two different key columns. One constructor makes them agree by
construction. Quantiles are type 4, which is SAS PCTLDEF=1, and are named
for what they are: conditional on selection, not a confidence interval.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `boot_bag()` builds its summary through `.bag_summary()`

**Files:**
- Modify: `R/boot-bag.R` - the `boot` element of the `bag` list, and the
  `@return` roxygen
- Test: `tests/testthat/test-boot-bag.R` (append)

**Interfaces:**
- Consumes: `.bag_summary(m)` from Task 1, returning the nine columns keyed
  `parameter`.
- Produces: a bag whose `$boot$summary` has those nine columns. Task 3 asserts
  the pooled shape equals this one.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-boot-bag.R`:

```r
test_that("the bag's summary is keyed parameter and carries the quantiles", {
  # Before this, boot_bag() filled the slot with boot_summary() unrenamed, so
  # the bag said `variable` while boot_validate()'s own documented example,
  # $boot$replicates and boot_health() all say `parameter`. The bag
  # contradicted its own validator's contract.
  set.seed(1)
  n <- 200
  x1 <- rnorm(n)
  df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1, x2 = rnorm(n))
  fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_rep = 20, seed = 42)
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 2L,
                  manifest = list(sha256 = "abc123"))

  expect_equal(names(bag$boot$summary),
               c("parameter", "n", "pct", "mean", "sd", "min", "max",
                 "sel_q025", "sel_q975"))
  expect_false("variable" %in% names(bag$boot$summary))
  expect_true(all(bag$boot$summary$parameter %in% colnames(fit$coefficients)))
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-bag")'`

Expected: FAIL on the `names()` comparison - the actual value is
`c("variable", "n", "pct", "mean", "sd", "min", "max")`.

- [ ] **Step 3: Change the one line that builds it**

In `R/boot-bag.R`, inside the `bag <- list(...)` call, change:

```r
      summary    = boot_summary(x),
```

to:

```r
      summary    = .bag_summary(m),
```

`m` is already in scope - it is `x$coefficients`, assigned earlier in the
function.

- [ ] **Step 4: Update the `@return` roxygen**

In `R/boot-bag.R`, find the `@return` tag and replace its text with:

```r
#' @return A list carrying the fields [boot_validate()] requires: `n_boot`,
#'   `seed`, `slentry`, `slstay`, `base_params`, `requested`, `usable`,
#'   `n_rows`, `elapsed_mins`, `manifest`, `engine`, and `boot`. `boot$summary`
#'   is keyed `parameter` -- as `boot$replicates` and [boot_health()] are, and
#'   as [boot_pool_chunks()] returns -- rather than [boot_summary()]'s
#'   `variable`, and carries `sel_q025` and `sel_q975` alongside the `%SUMBOOT`
#'   statistics. Those two are the spread of the coefficient across the
#'   replicates that **selected** it, not a confidence interval: a term chosen
#'   half the time has an interval over half the replicates.
```

Keep any other sentences already present in that `@return` block that describe
`dropped` or other fields; only the summary-shape sentences are new.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-bag")'`

Expected: PASS. The pre-existing `boot_bag()` tests must also still pass -
none of them reads `$boot$summary` by column name.

- [ ] **Step 6: Regenerate the documentation**

Run: `Rscript -e 'devtools::document()'`

Expected: `man/boot_bag.Rd` is rewritten. `NAMESPACE` must be unchanged - this
task adds no export.

- [ ] **Step 7: Commit**

```bash
git add R/boot-bag.R man/boot_bag.Rd tests/testthat/test-boot-bag.R
git commit -m "fix: key the bag's summary on parameter, as the bag contract says

boot_bag() filled \$boot\$summary with boot_summary() unrenamed, so the bag
said 'variable' while boot_validate()'s own documented example,
\$boot\$replicates and boot_health() all say 'parameter'.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: `boot_pool_chunks()` drops `ci_lower`/`ci_upper` for the shared constructor

**Files:**
- Modify: `R/boot-pool.R:197-211` - the `summ <- do.call(rbind, ...)` block and
  the reorder line that follows it
- Test: `tests/testthat/test-boot-pool.R` (append)

**Interfaces:**
- Consumes: `.bag_summary(m)` from Task 1; `.replicate_matrix(bag)`, the
  existing internal in `R/boot-frequencies.R`, which takes a list with
  `$boot$replicates` and `$n_boot` and returns the wide matrix with `NA` where
  a term was not selected.
- Produces: a pooled bag whose `$boot$summary` has the same nine columns as
  Task 2's bagged one.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-boot-pool.R`:

```r
test_that("the pooled summary has the same shape as the bagged one", {
  # These two built $boot$summary separately: seven columns keyed `variable`
  # from boot_bag(), nine keyed `parameter` here. A renderer saw the quantile
  # columns only if the run happened to be chunked.
  set.seed(1)
  n <- 200
  x1 <- rnorm(n)
  df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1, x2 = rnorm(n))
  fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_rep = 20, seed = 42)
  bagged <- boot_bag(fit, base_params = "(Intercept)", requested = 2L,
                     manifest = list(sha256 = "abc123"))

  pooled <- boot_pool_chunks(list(chunk(1), chunk(2)))

  expect_equal(names(pooled$boot$summary), names(bagged$boot$summary))
})

test_that("the pooled summary no longer claims to carry a confidence interval", {
  # ci_lower/ci_upper were computed over the NA-dropped replicates, so they
  # were conditional on selection and were not confidence intervals at all.
  p <- boot_pool_chunks(list(chunk(1), chunk(2)))

  expect_false("ci_lower" %in% names(p$boot$summary))
  expect_false("ci_upper" %in% names(p$boot$summary))
  expect_true(all(c("sel_q025", "sel_q975") %in% names(p$boot$summary)))
})
```

`chunk()` is the local helper already defined at the top of
`tests/testthat/test-boot-pool.R`; read it before writing these tests and use
it exactly as the existing tests in that file do.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-pool")'`

Expected: FAIL - the pooled names are
`c("parameter", "n", "pct", "mean", "sd", "min", "max", "ci_lower", "ci_upper")`
against the bagged nine, and `ci_lower` is present.

- [ ] **Step 3: Replace the hand-rolled summary with the shared constructor**

In `R/boot-pool.R`, delete this block entirely:

```r
  summ <- do.call(rbind, lapply(split(reps, reps$parameter), function(x) {
    n <- length(unique(x$replicate))
    data.frame(parameter = x$parameter[1],
               n         = n,
               pct       = 100 * n / n_boot,
               mean      = mean(x$estimate),
               sd        = stats::sd(x$estimate),
               min       = min(x$estimate),
               max       = max(x$estimate),
               ci_lower  = unname(stats::quantile(x$estimate, 0.025)),
               ci_upper  = unname(stats::quantile(x$estimate, 0.975)),
               row.names = NULL, stringsAsFactors = FALSE)
  }))
  summ <- summ[order(-summ$pct, summ$parameter), ]
```

and put this in its place:

```r
  # The same constructor boot_bag() uses, so the pooled and unpooled shapes
  # cannot drift apart. It also gets the pooling property this block used to
  # state for itself: `n` and `pct` are recomputed from the pooled replicates
  # rather than averaged across chunks, because a percentage of a percentage is
  # not a percentage of the whole and the chunks need not be the same size.
  summ <- .bag_summary(
    .replicate_matrix(list(boot = list(replicates = reps), n_boot = n_boot))
  )
```

`.bag_summary()` already orders by descending `n` then name. With `n_boot`
fixed across the pooled table that is the same order as the deleted
`order(-summ$pct, summ$parameter)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-pool")'`

Expected: PASS, including the pre-existing test "the pooled summary is
recomputed, not averaged", which asserts `pct` and `n` by `parameter` and must
be unaffected.

- [ ] **Step 5: Run the whole suite**

Run: `Rscript -e 'devtools::test()'`

Expected: PASS. `boot_frequencies()` rebuilds from `$boot$replicates` and never
reads `$boot$summary`, so nothing else in the package depends on either shape.

- [ ] **Step 6: Commit**

```bash
git add R/boot-pool.R tests/testthat/test-boot-pool.R
git commit -m "fix: stop calling a selection-conditional spread a confidence interval

ci_lower/ci_upper were quantiles over the NA-dropped replicates, so a term
selected in 30% of replicates got an interval over that 30% -- and the
weaker the term, the narrower the interval looked. Renamed to
sel_q025/sel_q975 and built through .bag_summary(), which also removes this
function's duplicate of the summary arithmetic.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `boot_validate()` checks the summary's columns

**Files:**
- Modify: `R/boot-validate.R` - the `nested` block around line 176, and the
  `@details` roxygen
- Test: `tests/testthat/test-boot-validate.R` (append)

**Interfaces:**
- Consumes: nothing from earlier tasks at runtime. The check is deliberately
  looser than `.bag_summary()`'s output - see Refinement 1 above.
- Produces: no new function. `boot_validate()` gains one failure mode.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-boot-validate.R`:

```r
test_that("a summary keyed variable rather than parameter is refused", {
  # This is the defect that shipped: boot_bag() filled the slot with
  # boot_summary() unrenamed. Nothing in the package reads $boot$summary, so
  # only a check here can catch the two constructors drifting apart again.
  bag <- fx_bag()
  names(bag$boot$summary)[names(bag$boot$summary) == "parameter"] <- "variable"

  expect_error(boot_validate(bag), "boot\\$summary")
})

test_that("a summary missing a count column is refused", {
  bag <- fx_bag()
  bag$boot$summary$n <- NULL

  expect_error(boot_validate(bag), "boot\\$summary")
})

test_that("the three columns a report reads are enough", {
  # Deliberately NOT the nine columns .bag_summary() produces. boot_validate()
  # accepts bags written by runners, and the fixture and this function's own
  # documented example both carry exactly parameter/n/pct. The nine-column
  # agreement between boot_bag() and boot_pool_chunks() is guaranteed by their
  # sharing .bag_summary(), which is stronger than a check here.
  expect_true(boot_validate(fx_bag()))
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-validate")'`

Expected: the first two FAIL - no error is raised, because the current check
only asks whether the `summary` slot is present.

- [ ] **Step 3: Add the check**

In `R/boot-validate.R`, in the `else` branch that currently reads:

```r
  } else {
    problems <- c(problems,
                  unlist(lapply(nested, function(f) {
                    .chk_any(bag[["boot"]][[f]], paste0("boot$", f))
                  }), use.names = FALSE))
  }
```

replace it with:

```r
  } else {
    problems <- c(problems,
                  unlist(lapply(nested, function(f) {
                    .chk_any(bag[["boot"]][[f]], paste0("boot$", f))
                  }), use.names = FALSE))
    # The columns a report reads, checked by name. Presence of the slot was
    # never enough: boot_bag() filled it with boot_summary() unrenamed, so the
    # bag said `variable` where every other bag field says `parameter`, and
    # nothing noticed, because nothing in this package reads the slot at all.
    #
    # Three columns rather than the nine .bag_summary() writes. This function
    # accepts bags from runners, and a runner reporting a frequency table and
    # nothing else is not malformed. The two constructors agree on all nine
    # because they share .bag_summary(), not because of this check.
    s <- bag[["boot"]][["summary"]]
    if (!is.null(s) && length(s)) {
      want <- c("parameter", "n", "pct")
      miss <- setdiff(want, names(s))
      if (length(miss)) {
        hint <- if ("variable" %in% names(s)) {
          paste0(". A summary keyed `variable` is boot_summary()'s shape, ",
                 "not a bag's")
        } else {
          ""
        }
        problems <- c(
          problems,
          paste0("boot$summary: expected the columns ",
                 paste(want, collapse = ", "), ", found ",
                 paste(names(s), collapse = ", "), hint)
        )
      }
    }
  }
```

Keep every line at or under 80 characters.

- [ ] **Step 4: Update the `@details` roxygen**

In `R/boot-validate.R`, in the `@details` block that describes the `boot`
element, add this sentence after the existing description of the four nested
fields:

```r
#' `boot$summary` is additionally checked for the columns `parameter`, `n` and
#' `pct` -- the ones a report reads. It is not required to carry the full shape
#' [boot_bag()] writes, because a runner may report a frequency table and
#' nothing more. A summary keyed `variable` is [boot_summary()]'s shape rather
#' than a bag's, and is refused by name.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "boot-validate")'`

Expected: PASS.

- [ ] **Step 6: Run the whole suite**

Run: `Rscript -e 'devtools::test()'`

Expected: PASS. In particular `fx_bag()` and `fx_bag_counts()` both build a
summary with `parameter`, `n` and `pct`, so every test that validates a fixture
bag - in `test-boot-frequencies.R`, `test-boot-health.R`,
`test-boot-concepts.R` and `test-boot-provenance.R` - must be unaffected. If
any of them fails, the check is too strict: re-read Refinement 1 rather than
editing the fixture.

- [ ] **Step 7: Regenerate the documentation and commit**

Run: `Rscript -e 'devtools::document()'`

```bash
git add R/boot-validate.R man/boot_validate.Rd tests/testthat/test-boot-validate.R
git commit -m "feat: check the bag summary's columns, not just its presence

Nothing in this package reads \$boot\$summary -- boot_frequencies() rebuilds
from \$boot\$replicates -- so the two constructors could disagree
indefinitely without a single test failing. They did.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: State the branch split, and close the loop on the spec

**Files:**
- Modify: `AGENTS.md` - the "Rules for this repo" list
- Modify: `README.md`
- Modify: `NEWS.md` - bullets under `# hvtiRbootstrap (unreleased)`
- Modify: `dev/specs/2026-09-02-bootstrap-branches-design.md` - the checklist

**Interfaces:**
- Consumes: the behaviour delivered by Tasks 1-4.
- Produces: nothing further tasks depend on. This is the last task.

- [ ] **Step 1: Add the branch-split rule to `AGENTS.md`**

In `AGENTS.md`, under "Rules for this repo", add this bullet after the
`boot_clusters()` `n_any` bullet:

```markdown
- **THIS PACKAGE DOES TWO JOBS, AND THEY ARE NOT THE SAME JOB.** *Selection*
  refits on each replicate and counts which terms survived - the replicates are
  a vote, and `NA` is how a vote is cast. *Intervals* resample to put a band
  around an estimate - the replicates are a distribution, nothing is selected,
  and there is no `NA` semantics at all. Everything shipped today is the
  selection branch. The interval branch (`%BNMNR`, `%BNPREV`, `bl_ord.*`) is
  specified in `dev/specs/2026-09-02-bootstrap-branches-design.md` and not
  built. A CI-shaped output computed on the selection branch is the mistake
  this rule exists to stop: `boot_pool_chunks()` shipped `ci_lower`/`ci_upper`
  that were quantiles over only the replicates that selected the term, so the
  weaker the term the narrower its "interval" looked. They are now
  `sel_q025`/`sel_q975`.
- **Coverage lives in a column name, never in an argument.** No function in
  this package takes a confidence level. The macro family hardcodes
  `PCTLPTS=2.5 16 50 84 97.5` and returns both the 95% and the 68% band in
  named columns; a function that takes no level cannot mislabel one, which is
  the point. Quantiles are `stats::quantile(type = 4)`, SAS's `PCTLDEF=1`,
  never R's `type = 7` default.
```

- [ ] **Step 2: Add the branch split to `README.md`**

Read `README.md` first and match its existing section structure. Add a short
section after whatever section introduces the six exports, worded for the CORR
biostatistician who already runs the macros:

```markdown
## Two branches, one resampling loop

Bootstrapping here does one of two jobs, and they are not the same job.

**Selection** - `%bootreg`, `%SUMBOOT`, `%cluster` - refits on every replicate
and counts which terms survived. The replicates are a vote, and a term the
model did not select is `NA`. That is the whole of what this package ships
today: `boot_select()`, `boot_summary()`, `boot_clusters()`, the fitters, and
the pooling and reporting layers around them.

**Intervals** - `%BNMNR`, `%BNPREV`, `bl_ord.*` - resample to put a band around
an estimate. Nothing is selected, so there is no `NA` semantics; the replicates
are a distribution. That branch is specified and not yet built.

No function here takes a confidence level. The macros do not either: they
hardcode `PCTLPTS=2.5 16 50 84 97.5` and return both the 95% and the 68% band
in columns named for their coverage, so there is no level to mislabel.
```

- [ ] **Step 3: Add the `NEWS.md` bullets**

In `NEWS.md`, under the existing `# hvtiRbootstrap (unreleased)` heading, add:

```markdown
* **`boot_pool_chunks()` no longer reports a confidence interval it never
  computed.** `ci_lower` and `ci_upper` were quantiles taken over the
  replicates in which the term was *selected*, because `boot_bag()` writes
  `$boot$replicates` with `NA` dropped. For a term chosen in 30% of replicates
  that was an interval over 30% of them, and the weaker the term, the narrower
  its interval looked. They are now `sel_q025` and `sel_q975`, named for what
  they are: a sibling of `mean`, `sd`, `min` and `max`, which are conditional
  on selection in exactly the same way.
* **`boot_bag()` and `boot_pool_chunks()` now build `$boot$summary` through one
  constructor**, so the two cannot disagree. They had been building it
  separately, in two shapes with two different key columns -- `variable` from
  the bag, `parameter` from the pool -- so a renderer saw a different shape
  depending on whether the run happened to be chunked, and `boot_bag()`
  contradicted the key that `boot_validate()`'s own documented example uses.
  Both now key on `parameter`. `boot_summary()` is unchanged and keeps
  `variable`: it is the standalone `%SUMBOOT` port, not a bag.
* **`boot_validate()` checks `$boot$summary`'s columns**, not merely that the
  slot is filled. Nothing in the package reads that slot -- `boot_frequencies()`
  rebuilds from `$boot$replicates` -- so without this the two constructors
  could drift apart indefinitely without a test failing.
* Quantiles on the selection branch use `stats::quantile(type = 4)`, which is
  SAS `PROC STDIZE`'s `PCTLDEF=1`, rather than R's `type = 7` default.
```

Do **not** change `DESCRIPTION`'s `Version:`, and do not add a new version
heading. See Refinement 2.

- [ ] **Step 4: Correct the spec's checklist**

In `dev/specs/2026-09-02-bootstrap-branches-design.md`, in the "Definition of
done" section, tick the items Tasks 1-4 delivered and replace the final line:

```markdown
- [ ] Patch bump and `NEWS.md` bullets under the current heading
```

with:

```markdown
- [x] `NEWS.md` bullets under the standing `(unreleased)` heading. **No version
      bump:** `AGENTS.md` says to bump when you tag, not when you merge, and
      `tests/testthat/test-package.R` skips unversioned headings so that work
      can merge under `(unreleased)`. This line previously said "patch bump",
      which was wrong under that convention.
```

Also add, under "Two refinements", a note that `boot_validate()` checks three
columns rather than nine, matching Refinement 1 in
`docs/plans/2026-09-02-bootstrap-branch-split.md`.

- [ ] **Step 5: Run the full release gate**

Run: `Rscript -e 'devtools::document()'`

Then: `Rscript -e 'devtools::test()'`

Expected: PASS, whole suite.

Then: `Rscript -e 'devtools::check()'`

Expected: **0 errors, 0 warnings, 0 notes.** If a note appears about an empty
`inst/doc` or hidden files, you are checking the working tree rather than a
clean export - build from `git archive` as `AGENTS.md` describes.

Then: `Rscript -e 'lintr::lint_package()'`

Expected: no output. Remember the 80-character limit - there is no `.lintr`.

- [ ] **Step 6: Commit and open the PR**

```bash
git add AGENTS.md README.md NEWS.md dev/specs/2026-09-02-bootstrap-branches-design.md man/
git commit -m "docs: state the branch split, and record the columns that changed

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Then open a pull request. Never push to `main`; it is protected by a ruleset
named 'protect main' that permits pull requests only.

The PR description must state the downstream break explicitly:
`hvtiRtemplates` `04.02`-`04.05` read `$boot$summary`, and both the key column
(`variable` to `parameter` on the bagged path) and the quantile column names
(`ci_lower`/`ci_upper` to `sel_q025`/`sel_q975`) change. Their template floor
of `hvtiRbootstrap >= 0.9.0` needs raising once this is tagged.

---

## What this plan does not do

Named so that an implementer does not improvise them:

- **`boot_predict_ci()` is not built here.** The interval branch is specified in
  the design note and deferred to its own spec, alongside the hazard fitter, the
  quantile fitter (hvtiRbootstrap#16) and penalised selection.
- **No `conf` argument is added anywhere.** That is the design, not an
  oversight - see the design note's coverage section.
- **`boot_summary()` is not touched.** It keeps its `variable` key and its seven
  columns. It is held to exact parity with `%SUMBOOT` and is not a bag.
- **The `bn` parity fixture is not captured here.** It is worth doing before the
  SAS licence expires on 2026-09-29, but it belongs to the interval branch's
  spec.
