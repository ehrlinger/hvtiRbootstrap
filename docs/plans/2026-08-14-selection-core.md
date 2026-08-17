# hvtiRbootstrap v1 - Selection Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port `%bootreg`, `%SUMBOOT` and `%cluster` into an R package whose selection results can be checked against the SAS originals.

**Architecture:** One resampling engine (`boot_select()`) parameterised by a *fitter*, mirroring `%bootreg`'s `PROC=`; a deterministic summariser (`boot_summary()`) that is the parity-tested core; and cluster-aware aggregation (`boot_clusters()`). A variable that is not selected in a replicate has a missing coefficient - that is how `n` becomes selection frequency, and it is the hinge the whole design turns on.

**Tech Stack:** R (>= 4.1.0), testthat 3e, roxygen2, survival (Cox fitter), pkgdown.

## Global Constraints

- Spec: `docs/specs/2026-08-14-hvtirbootstrap-design.md`. Read it before Task 1.
- SAS source of truth: `~/Documents/macro.library/bootstrap.models.sas` (`%bootreg`), `bootstrap.summary.sas` (`%SUMBOOT`), `bootstrap.clusters.sas` (`%cluster`). **Read the macro before porting it. Do not port from this plan's prose alone.**
- **Parity is exact for `boot_summary()` and `boot_clusters()` only.** Resampling and model fitting are explicitly not parity-tested (stochastic; and the fitters belong to `glm`/`lm`/`coxph`).
- **No cohort data in the package.** All fixtures are synthetic. This corpus has a PHI history; nothing derived from a study tree enters this repo.
- ASCII only in R source string literals. Use `\uXXXX` escapes if a symbol is needed.
- Version stays `0.1.0` for the whole plan. Do not bump; the maintainer cuts releases.
- All work lands on one branch, `feat/selection-core`; `main` stays clean. **Updated 2026-08-17:** the remote now exists (`github.com/ehrlinger/hvtiRbootstrap`, public, matching the sibling packages), so Task 6 ends in a real push and PR rather than a local-only branch.
- `Config/testthat/edition: 3`, roxygen with markdown, GPL-3.

---

## Deviations from SAS - the register

**Standing rule for this plan: the port is CORRECT first, faithful second.** Where
the macro's behaviour and its documented intent disagree, implement the intent
and record the deviation. Every deviation must land in three places, or it is not
done:

1. **The roxygen** of the function that deviates, so `?fn` says so.
2. **A test** asserting the deviating behaviour, so it cannot silently revert.
3. **This register**, and the README's "Divergence from the SAS macros" section.

When a task hits a deviation not listed below, **stop and surface it** rather
than deciding quietly. Add it here with the same three artefacts.

### D1 - `fraction` is applied (Task 3) - CONFIRMED 2026-08-14

`%bootreg` documents `FRACTION=` but never applies it: line 71 computes
`%let size=&ds_size*&fraction`, line 72 prints it, and it is never referenced
again; the resample loop at line 82 reads `do _counter=1 to &ds_size`. The macro
always draws *n* rows regardless.

`boot_select()` draws `round(n * fraction)` rows. A parameter that silently does
nothing is a defect, not a method.

⚠️ **Consequence to state plainly:** any filed CORR result produced with
`FRACTION` other than 1.0 was **not** subsampled, so R will disagree with it.
`fraction = 1` (the default) matches SAS exactly.

### D2 - stepwise selects on AIC, not p-values (Task 2) - inherent

`%bootreg` passes `SLE=`/`SLS=` to SAS `SELECTION=STEPWISE`, which are p-value
thresholds for entry and retention. R's [stats::step()] selects on AIC. The two
cannot agree term for term.

`sle` and `sls` are carried on the interface for fidelity and are documented as
not reproducing SAS's thresholds. This is *why* model fitting sits outside the
parity claim - see the spec's parity table. Closing it would mean writing a
p-value stepwise selector, which is a separate decision, not a task in this plan.

### D3 - the retry loop is capped (Task 3) - CONFIRMED 2026-08-17

`%bootreg`'s resampling loop is `%do %while(&sample<&resampl)`, and `&sample`
advances only when `&regrc=0`. A model specification that fails on *every*
replicate therefore never terminates: `&tsamples` climbs forever and `&sample`
never moves. The macro has no cap.

In SAS that is survivable - a batch job has a wall clock and an operator
watching the log. In R it is not: `boot_select()` runs inside `test_dir()` and
`R CMD check`, where an unbounded loop hangs CI with no output and no
diagnostic. The failure mode is easy to reach, because the fitters swallow
**warnings** as well as errors (Task 2), so a separable logistic fit or a
misspecified formula returns `NULL` on every draw.

`boot_select()` therefore takes `max_attempts = 10 * n_rep` and errors when the
budget is exhausted, reporting how many valid models it managed. The error is
the diagnostic the macro never gives you: it means the model could not be fitted
on the data, not that the resampler is slow.

⚠️ **Consequence to state plainly:** a run that SAS would have ground through -
one where valid fits are rarer than 1 in 10 - now errors instead of eventually
finishing. Raise `max_attempts` to restore the macro's behaviour; `Inf` removes
the cap entirely and reproduces `%bootreg` exactly.

## File Structure

| Path | Responsibility |
|---|---|
| `DESCRIPTION`, `NAMESPACE`, `.Rbuildignore`, `.gitignore`, `LICENSE.md`, `NEWS.md`, `README.md` | package skeleton |
| `.github/workflows/{R-CMD-check,lint,test-coverage}.yaml` | CI |
| `R/fitters.R` | the fitter contract and `fit_logistic()`, `fit_linear()`, `fit_cox()` |
| `R/boot-select.R` | `boot_select()` - resample, fit, retry-on-failure, assemble |
| `R/boot-class.R` | the `boot_selection` class: constructor, `print`, `summary` |
| `R/boot-summary.R` | `boot_summary()` - the `%SUMBOOT` port |
| `R/boot-clusters.R` | `boot_clusters()` - the `%cluster` port |
| `tests/testthat/helper-fixtures.R` | synthetic replicate tables shared by tests |
| `tests/testthat/test-*.R` | one file per R file above |

---

### Task 1: Package skeleton that checks clean

**Files:**
- Create: `DESCRIPTION`, `.Rbuildignore`, `.gitignore`, `LICENSE.md`, `NEWS.md`, `README.md`, `hvtiRbootstrap.Rproj`, `R/hvtiRbootstrap-package.R`, `tests/testthat.R`, `.github/workflows/R-CMD-check.yaml`
- Test: `tests/testthat/test-package.R`

**Interfaces:**
- Consumes: nothing.
- Produces: an installable package named `hvtiRbootstrap` at version `0.1.0`, with `testthat` edition 3 wired up. Later tasks add functions to `R/`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-package.R`:

```r
test_that("the package is loadable and correctly identified", {
  expect_equal(as.character(utils::packageVersion("hvtiRbootstrap")), "0.1.0")
})
```

- [ ] **Step 2: Run it and watch it fail**

Run: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-package.R")'`
Expected: FAIL  -  there is no package yet.

- [ ] **Step 3: Write DESCRIPTION**

```
Package: hvtiRbootstrap
Title: Bootstrap Model Building for the HVTI CORR Group
Version: 0.1.0
Authors@R:
    person("John", "Ehrlinger", , "ehrlinj@ccf.org", role = c("aut", "cre"))
Description: Builds models by bootstrap resampling, in the manner of the
    Cleveland Clinic CORR group's SAS macro library: fit a model on each of
    many bootstrap replicates, record which variables survive selection, and
    report how often each appeared. Ports the 'bootreg', 'SUMBOOT' and
    'cluster' macros.
License: GPL-3
Encoding: UTF-8
Depends:
    R (>= 4.1.0)
Imports:
    stats
Suggests:
    survival,
    testthat (>= 3.0.0)
Config/testthat/edition: 3
Roxygen: list(markdown = TRUE)
```

**Do not add `RoxygenNote:` by hand.** `devtools::document()` writes
`Config/roxygen2/version:` itself, matching the roxygen2 actually installed -
8.1.0, the same field `hvtiRtables` and `hvtiRtemplates` carry. Let the tool
write it and commit what it produces; hand-restoring a version string fights
the generator and will drift.

- [ ] **Step 4: Write the remaining skeleton files**

`R/hvtiRbootstrap-package.R`:

```r
#' @keywords internal
"_PACKAGE"
```

`tests/testthat.R`:

```r
library(testthat)
library(hvtiRbootstrap)

test_check("hvtiRbootstrap")
```

`.Rbuildignore`:

```
^.*\.Rproj$
^\.Rproj\.user$
^\.github$
^\.superpowers$
^docs$
^README\.md$
^LICENSE\.md$
```

`^\.superpowers$` keeps this plan's own scratch directory out of the build;
without it `R CMD check` reports a "hidden files and directories" NOTE.

`.gitignore`:

```
.Rproj.user
.Rhistory
.RData
*.tar.gz
*.Rcheck
```

`NEWS.md`:

```markdown
# hvtiRbootstrap 0.1.0

* Initial development version. Selection core only: `boot_select()`,
  `boot_summary()`, `boot_clusters()`, with logistic, linear and Cox fitters.
```

`README.md`:

```markdown
# hvtiRbootstrap

Bootstrap model building for the HVTI CORR group - the R port of the SAS
`%bootreg` / `%SUMBOOT` / `%cluster` macros.

Fit a model on each of many bootstrap replicates, record which variables
survive selection, and report how often each appeared.

Destination for 31 macro-library files, assigned by the allocation map in
`hvtiRtemplates:specs/2026-08-14-macro-allocation-design.md`. Design and scope:
`docs/specs/2026-08-14-hvtirbootstrap-design.md`.

## Status

Under development. v1 covers the selection core with logistic, linear and Cox
fitters. Hazard and quantile fitters, the bootstrap-CI family, and penalised
selection are each deferred to their own spec.
```

`LICENSE.md`: copy the GPL-3 text from `~/Documents/GitHub/hvtiRtables/LICENSE.md`.

`hvtiRbootstrap.Rproj`: copy from `~/Documents/GitHub/hvtiRtables/hvtiRtables.Rproj`.

`.github/workflows/R-CMD-check.yaml`: copy from `~/Documents/GitHub/hvtiRtables/.github/workflows/R-CMD-check.yaml` unchanged  -  it is repo-agnostic.

- [ ] **Step 5: Run the test and the check**

Run: `Rscript -e 'devtools::document(); devtools::install(quick = TRUE, upgrade = FALSE); testthat::test_dir("tests/testthat")'`
Expected: PASS, 1 test.

Run: `Rscript -e 'devtools::check(document = FALSE)'`
Expected: 0 errors, 0 warnings. One NOTE for "New submission" is acceptable; anything else must be fixed now, not later.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: package skeleton at 0.1.0"
```

---

### Task 2: The fitter contract and three fitters

**Files:**
- Create: `R/fitters.R`, `tests/testthat/test-fitters.R`

**Interfaces:**
- Consumes: nothing from Task 1 beyond the package existing.
- Produces: `fit_logistic(data, formula, select)`, `fit_linear(...)`, `fit_cox(...)`. Each returns a **named numeric vector of coefficients** for the variables the model kept, or `NULL` if the fit failed. `select` is a list with elements `method` (`"stepwise"` or `"none"`), `sle`, `sls`, `max_steps`. `boot_select()` in Task 3 calls these and treats `NULL` as "invalid replicate, resample again".

**Why `NULL` and not an error:** `%bootreg` checks `&regrc` after each `proc` and, when non-zero, resamples in place without counting the attempt. Returning `NULL` is that contract in R.

**Why a named vector:** `%bootreg` writes `outest=est`, one row per replicate, with a **missing coefficient for any variable not selected**. That missingness is what `%SUMBOOT` counts. Task 3 assembles these vectors into a matrix with `NA` in the gaps, reproducing `outest`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-fitters.R`:

```r
make_df <- function(n = 200, seed = 1) {
  set.seed(seed)
  x1 <- rnorm(n); x2 <- rnorm(n); noise <- rnorm(n)
  data.frame(
    y  = as.integer(x1 + rnorm(n) > 0),
    yc = x1 * 2 + rnorm(n),
    x1 = x1, x2 = x2, noise = noise
  )
}

test_that("fit_linear returns a named numeric vector of kept coefficients", {
  out <- fit_linear(make_df(), yc ~ x1 + x2 + noise,
                    list(method = "none", sle = 0.10, sls = 0.05, max_steps = 0))
  expect_type(out, "double")
  expect_true(!is.null(names(out)))
  expect_true("x1" %in% names(out))
})

test_that("fit_logistic keeps only selected variables under stepwise", {
  out <- fit_logistic(make_df(), y ~ x1 + x2 + noise,
                      list(method = "stepwise", sle = 0.10, sls = 0.05, max_steps = 0))
  expect_type(out, "double")
  # x1 drives y by construction; pure noise should usually drop out. The
  # assertion is on the CONTRACT (a subset of the offered terms), not on which
  # variables win -- that is the model's business and varies by replicate.
  expect_true(all(names(out) %in% c("(Intercept)", "x1", "x2", "noise")))
})

test_that("a fitter returns NULL rather than erroring on an impossible fit", {
  df <- make_df()
  df$y <- 0L                      # no variation in the response
  out <- fit_logistic(df, y ~ x1,
                      list(method = "none", sle = 0.10, sls = 0.05, max_steps = 0))
  expect_null(out)
})

test_that("fit_cox returns named coefficients without an intercept", {
  skip_if_not_installed("survival")
  set.seed(2)
  df <- data.frame(time = rexp(200), status = rbinom(200, 1, 0.7),
                   x1 = rnorm(200), x2 = rnorm(200))
  out <- fit_cox(df, survival::Surv(time, status) ~ x1 + x2,
                 list(method = "none", sle = 0.10, sls = 0.05, max_steps = 0))
  expect_type(out, "double")
  expect_false("(Intercept)" %in% names(out))
})
```

- [ ] **Step 2: Run it and watch it fail**

Run: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-fitters.R")'`
Expected: FAIL  -  `could not find function "fit_linear"`.

- [ ] **Step 3: Write the implementation**

Create `R/fitters.R`:

```r
# Fitter contract
# ---------------
# A fitter takes (data, formula, select) and returns a NAMED NUMERIC VECTOR of
# the coefficients the model kept, or NULL if the fit failed.
#
# NULL rather than an error is deliberate: %bootreg checks &regrc after each
# proc and, when it is non-zero, resamples in place WITHOUT counting the
# attempt. Returning NULL is that contract -- boot_select() drops the replicate
# and draws another.
#
# A named vector rather than a model object is also deliberate: %bootreg writes
# outest=, one row per replicate, with a MISSING coefficient for any variable
# not selected. That missingness is exactly what %SUMBOOT counts, so the vector
# must carry only the kept terms and let the assembler supply NA elsewhere.

# CORRECTED 2026-08-17. Two fixes, both discovered by the tests failing.
#
# (a) `.select_scope()` as originally drafted was never called, and wiring it in
#     is unnecessary: with `scope` missing, step() fixes the addable set to the
#     STARTING model's terms, so a dropped term can be re-admitted and
#     direction = "both" is already genuine stepwise from a full model. It would
#     also have been wrong for Cox -- all.vars(formula)[1] on
#     `Surv(time, status) ~ x1` returns "time", not the Surv() response. Dropped.
#
# (b) stepwise fitting needs TWO scope fixes, not one. step() resolves `data`
#     down two independent paths: add1()/drop1() build a model frame in
#     environment(formula(object)), and the refit runs
#     eval.parent(update(object, ..., evaluate = FALSE)), which looks in the
#     frame of step()'s CALLER. `.fit_in_env()` covers the first; `.maybe_step()`
#     taking a `data` argument it never references covers the second. With
#     either one missing, every stepwise replicate returns NULL -- and since
#     stepwise is boot_select()'s default, the whole package returns nothing.

.fit_in_env <- function(cl, formula, data) {
  env <- new.env(parent = environment(formula))
  environment(formula) <- env
  env$data <- data
  env$formula <- formula
  eval(cl, env)
}

# Stepwise both-directions, the closest R analogue to SAS SELECTION=STEPWISE.
# %bootreg's sle/sls are p-value thresholds; step() works on AIC, so the two
# cannot agree term for term. This is why fitting is NOT parity-tested: the
# selection mechanism is the model engine's, and the package's parity claim is
# scoped to the summariser. See the spec's parity table.
.maybe_step <- function(fit, select, data) {
  if (!identical(select$method, "stepwise")) return(fit)
  steps <- if (isTRUE(select$max_steps > 0)) select$max_steps else 1000L
  stats::step(fit, direction = "both", trace = 0, steps = steps)
}

.coefs <- function(fit) {
  cf <- stats::coef(fit)
  cf <- cf[!is.na(cf)]
  if (length(cf) == 0L) return(NULL)
  cf
}

#' Fit a linear model for one bootstrap replicate
#'
#' @param data A data frame - one bootstrap replicate.
#' @param formula Model formula offering the candidate terms.
#' @param select List with `method` (`"stepwise"` or `"none"`), `sle`, `sls`,
#'   `max_steps`. `%bootreg` equivalents: `SELECT=`, `SLE=`, `SLS=`, `MAXSTEP=`.
#' @return Named numeric vector of kept coefficients, or `NULL` if the fit
#'   failed. `NULL` tells [boot_select()] to discard the replicate and draw
#'   another, reproducing `%bootreg`'s `&regrc` check.
#' @export
fit_linear <- function(data, formula, select) {
  tryCatch({
    fit <- .fit_in_env(quote(stats::lm(formula, data = data)), formula, data)
    .coefs(.maybe_step(fit, select, data))
  }, error = function(e) NULL, warning = function(w) NULL)
}

#' Fit a logistic model for one bootstrap replicate
#'
#' @inheritParams fit_linear
#' @return Named numeric vector of kept coefficients, or `NULL`.
#' @export
fit_logistic <- function(data, formula, select) {
  tryCatch({
    fit <- .fit_in_env(quote(stats::glm(formula, data = data, family = stats::binomial())), formula, data)
    if (!fit$converged) return(NULL)
    .coefs(.maybe_step(fit, select, data))
  }, error = function(e) NULL, warning = function(w) NULL)
}

#' Fit a Cox proportional-hazards model for one bootstrap replicate
#'
#' @inheritParams fit_linear
#' @return Named numeric vector of kept coefficients, or `NULL`. Cox models
#'   carry no intercept, so none appears in the result.
#' @export
fit_cox <- function(data, formula, select) {
  if (!requireNamespace("survival", quietly = TRUE))
    stop("`fit_cox()` needs the survival package.", call. = FALSE)
  tryCatch({
    fit <- .fit_in_env(quote(survival::coxph(formula, data = data)), formula, data)
    .coefs(.maybe_step(fit, select, data))
  }, error = function(e) NULL, warning = function(w) NULL)
}
```

- [ ] **Step 4: Run the tests**

Run: `Rscript -e 'devtools::document(); devtools::load_all("."); testthat::test_file("tests/testthat/test-fitters.R")'`
Expected: PASS, 5 test_that blocks (11 expectations).

- [ ] **Step 5: Commit**

```bash
git add R/fitters.R man/ NAMESPACE tests/testthat/test-fitters.R
git commit -m "feat: fitter contract with logistic, linear and Cox fitters"
```

---

### Task 3: `boot_select()` - resample, fit, retry, assemble

**Files:**
- Create: `R/boot-select.R`, `R/boot-class.R`, `tests/testthat/test-boot-select.R`

**Interfaces:**
- Consumes: `fit_logistic()`, `fit_linear()`, `fit_cox()` from Task 2 - each `(data, formula, select) -> named numeric vector or NULL`.
- Produces: `boot_select(data, formula, fitter, n_rep = 1000, fraction = 1, select = "stepwise", sle = 0.10, sls = 0.05, max_steps = 0, max_attempts = 10 * n_rep, seed = NULL)` returning an object of class `boot_selection`: a list with `$coefficients` (a numeric matrix, one row per valid replicate, one column per candidate term, `NA` where the term was not selected), `$n_rep`, `$n_attempts`, `$call`. Task 4's `boot_summary()` consumes `$coefficients`.

**The hinge:** a term not selected in a replicate is `NA` in that row. `boot_summary()` counts non-missing values per column, so `n` *is* the selection frequency. Do not fill `NA` with zero.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-boot-select.R`:

```r
sim_df <- function(n = 150, seed = 7) {
  set.seed(seed)
  x1 <- rnorm(n)
  data.frame(yc = 2 * x1 + rnorm(n), x1 = x1, x2 = rnorm(n), noise = rnorm(n))
}

test_that("boot_select returns one row per requested replicate", {
  out <- boot_select(sim_df(), yc ~ x1 + x2 + noise, fit_linear,
                     n_rep = 25, select = "none", seed = 42)
  expect_s3_class(out, "boot_selection")
  expect_equal(nrow(out$coefficients), 25L)
  expect_equal(out$n_rep, 25L)
})

test_that("unselected terms are NA, not zero -- this is what makes n a frequency", {
  out <- boot_select(sim_df(), yc ~ x1 + x2 + noise, fit_linear,
                     n_rep = 25, select = "stepwise", seed = 42)
  expect_true(anyNA(out$coefficients))
  expect_false(any(out$coefficients == 0, na.rm = TRUE))
})

test_that("every candidate term gets a column even if never selected", {
  out <- boot_select(sim_df(), yc ~ x1 + x2 + noise, fit_linear,
                     n_rep = 10, select = "stepwise", seed = 1)
  expect_true(all(c("x1", "x2", "noise") %in% colnames(out$coefficients)))
})

test_that("a failing replicate is retried, not counted -- %bootreg's regrc check", {
  # A fitter that fails the first 5 calls then succeeds. n_rep valid models must
  # still be produced, and n_attempts must exceed n_rep.
  calls <- 0
  flaky <- function(data, formula, select) {
    calls <<- calls + 1
    if (calls <= 5) return(NULL)
    fit_linear(data, formula, select)
  }
  out <- boot_select(sim_df(), yc ~ x1, flaky, n_rep = 10,
                     select = "none", seed = 3)
  expect_equal(nrow(out$coefficients), 10L)
  expect_gt(out$n_attempts, out$n_rep)
})

test_that("seed makes a run reproducible", {
  a <- boot_select(sim_df(), yc ~ x1 + x2, fit_linear, n_rep = 10,
                   select = "none", seed = 99)
  b <- boot_select(sim_df(), yc ~ x1 + x2, fit_linear, n_rep = 10,
                   select = "none", seed = 99)
  expect_equal(a$coefficients, b$coefficients)
})

test_that("fraction subsamples -- a DELIBERATE divergence from %bootreg", {
  # %bootreg computes `size = ds_size * fraction` at line 71, prints it at 72,
  # and never uses it: the resample loop at line 82 reads `do _counter=1 to
  # &ds_size`. FRACTION is documented but inert there. We implement it, because
  # a parameter that silently does nothing is a defect. See the plan's
  # "A decision this plan encodes".
  n_seen <- NULL
  spy <- function(data, formula, select) {
    n_seen <<- c(n_seen, nrow(data))
    fit_linear(data, formula, select)
  }
  boot_select(sim_df(n = 100), yc ~ x1, spy, n_rep = 3,
              fraction = 0.5, select = "none", seed = 5)
  expect_true(all(n_seen == 50))
})

test_that("a Cox run gets no phantom (Intercept) column", {
  skip_if_not_installed("survival")
  set.seed(11)
  df <- data.frame(time = rexp(120), status = rbinom(120, 1, 0.7),
                   x1 = rnorm(120), x2 = rnorm(120))
  out <- boot_select(df, survival::Surv(time, status) ~ x1 + x2, fit_cox,
                     n_rep = 5, select = "none", seed = 4)
  # Cox has no intercept. Hardcoding one would give an all-NA column that
  # boot_summary() reports as a variable with n = 0 -- a phantom term.
  expect_false("(Intercept)" %in% colnames(out$coefficients))
})

test_that("boot_select rejects a fraction outside (0, 1]", {
  expect_error(
    boot_select(sim_df(), yc ~ x1, fit_linear, n_rep = 2, fraction = 0),
    "`fraction` must be greater than 0 and at most 1", fixed = TRUE
  )
})

test_that("a fitter that always fails errors instead of looping forever -- D3", {
  # %bootreg would spin here indefinitely: &sample never advances and there is
  # no cap. Under R CMD check that is an unbounded hang with no diagnostic, so
  # boot_select() budgets attempts and reports what it managed.
  never <- function(data, formula, select) NULL
  expect_error(
    boot_select(sim_df(), yc ~ x1, never, n_rep = 10, select = "none",
                max_attempts = 25, seed = 1),
    "gave up after 25 attempts with 0 valid models of 10 requested",
    fixed = TRUE
  )
})

test_that("max_attempts = Inf restores %bootreg's uncapped loop", {
  # Not a hang: this fitter succeeds, so the loop terminates normally. The
  # assertion is that Inf is ACCEPTED, which is the documented escape hatch
  # back to exact macro behaviour.
  out <- boot_select(sim_df(), yc ~ x1, fit_linear, n_rep = 5,
                     select = "none", max_attempts = Inf, seed = 8)
  expect_equal(nrow(out$coefficients), 5L)
})
```

- [ ] **Step 2: Run it and watch it fail**

Run: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-boot-select.R")'`
Expected: FAIL  -  `could not find function "boot_select"`.

- [ ] **Step 3: Write the class**

Create `R/boot-class.R`:

```r
new_boot_selection <- function(coefficients, n_rep, n_attempts, call) {
  structure(
    list(coefficients = coefficients, n_rep = n_rep,
         n_attempts = n_attempts, call = call),
    class = "boot_selection"
  )
}

#' @export
print.boot_selection <- function(x, ...) {
  cat("<boot_selection>\n")
  cat("  replicates: ", x$n_rep, " valid of ", x$n_attempts, " attempts\n",
      sep = "")
  cat("  terms:      ", ncol(x$coefficients), "\n", sep = "")
  cat("Use boot_summary() for per-variable selection frequencies.\n")
  invisible(x)
}

#' @export
summary.boot_selection <- function(object, ...) boot_summary(object)
```

- [ ] **Step 4: Write `boot_select()`**

Create `R/boot-select.R`:

```r
#' Build a model by bootstrap resampling
#'
#' Fits `fitter` on each of `n_rep` bootstrap replicates and records the
#' coefficients each model kept. A term the model did not select is `NA` in that
#' replicate's row, so [boot_summary()] can count non-missing values to get a
#' selection frequency. The R port of `%bootreg`
#' (`~/Documents/macro.library/bootstrap.models.sas`).
#'
#' @param data A data frame.
#' @param formula Model formula offering the candidate terms.
#' @param fitter A fitter such as [fit_logistic()], [fit_linear()] or
#'   [fit_cox()]. `%bootreg` equivalent: `PROC=`.
#' @param n_rep Number of **valid** models to generate (`%bootreg` `RESAMPL=`).
#'   Replicates whose fit fails are redrawn and do not count, matching the
#'   macro's `&regrc` check.
#' @param fraction Fraction of `nrow(data)` to draw per replicate
#'   (`%bootreg` `FRACTION=`). **Divergence:** the macro documents this
#'   parameter but never applies it - it computes `ds_size * fraction`, prints
#'   it, and then always draws `ds_size` rows. This implementation applies it.
#'   Pass `fraction = 1` (the default) to match SAS behaviour exactly.
#' @param select `"stepwise"` or `"none"` (`%bootreg` `SELECT=`/`FIXED=`).
#' @param sle,sls Entry and retention criteria (`%bootreg` `SLE=`, `SLS=`).
#'   Carried for interface fidelity; R's [stats::step()] selects on AIC, so
#'   these do not reproduce SAS's p-value thresholds term for term. Model
#'   fitting is not parity-tested - see the package's design spec.
#' @param max_steps Maximum selection steps, `0` for no limit (`%bootreg`
#'   `MAXSTEP=`).
#' @param max_attempts Budget of resampling attempts before giving up.
#'   **Divergence:** `%bootreg` has no such cap - its loop advances only on a
#'   successful fit, so a model that fails on every replicate never terminates.
#'   That is survivable in a batch job with an operator watching; under
#'   `R CMD check` it is an unbounded hang. Exhausting the budget raises an
#'   error reporting how many valid models were obtained. Pass `Inf` to restore
#'   the macro's uncapped behaviour.
#' @param seed Optional integer for reproducibility.
#' @return An object of class `boot_selection`. `$coefficients` is a matrix with
#'   one row per valid replicate and one column per candidate term, `NA` where
#'   the term was not selected.
#' @export
boot_select <- function(data, formula, fitter, n_rep = 1000, fraction = 1,
                        select = c("stepwise", "none"), sle = 0.10, sls = 0.05,
                        max_steps = 0, max_attempts = 10 * n_rep, seed = NULL) {
  select <- match.arg(select)
  if (!is.data.frame(data) || nrow(data) == 0L)
    stop("`data` must be a data frame with at least one row.", call. = FALSE)
  if (!is.numeric(fraction) || length(fraction) != 1L ||
        is.na(fraction) || fraction <= 0 || fraction > 1)
    stop("`fraction` must be greater than 0 and at most 1.", call. = FALSE)
  if (!is.numeric(n_rep) || length(n_rep) != 1L || n_rep < 1)
    stop("`n_rep` must be a positive number of replicates.", call. = FALSE)
  if (!is.numeric(max_attempts) || length(max_attempts) != 1L ||
        is.na(max_attempts) || max_attempts < n_rep)
    stop("`max_attempts` must be a single number at least as large as `n_rep`.",
         call. = FALSE)
  if (!is.null(seed)) set.seed(seed)

  n <- nrow(data)
  draw <- max(1L, round(n * fraction))
  ctrl <- list(method = select, sle = sle, sls = sls, max_steps = max_steps)
  terms_all <- attr(stats::terms(formula, data = data), "term.labels")

  fits <- vector("list", n_rep)
  kept <- 0L
  attempts <- 0L
  # %bootreg's loop: keep resampling until n_rep VALID models exist. A failed
  # fit is redrawn in place and does not count toward n_rep, only toward
  # attempts -- the macro reports both.
  # D3: the budget is ours, not the macro's. %bootreg would spin here forever
  # when no replicate ever fits; that is a hang with no diagnostic under
  # R CMD check, so we stop and say what we managed. max_attempts = Inf is the
  # documented way back to the macro's behaviour.
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

  # Columns are the offered terms plus whatever the fitters actually returned.
  # "(Intercept)" is NOT hardcoded: Cox models have none, and manufacturing one
  # would put an all-NA column in every Cox result that boot_summary() would
  # then report as a variable with n = 0.
  seen <- unique(unlist(lapply(fits, names), use.names = FALSE))
  cols <- unique(c(intersect("(Intercept)", seen), terms_all, seen))
  m <- matrix(NA_real_, nrow = n_rep, ncol = length(cols),
              dimnames = list(NULL, cols))
  for (i in seq_len(n_rep)) m[i, names(fits[[i]])] <- fits[[i]]

  new_boot_selection(m, n_rep = as.integer(n_rep),
                     n_attempts = attempts, call = match.call())
}
```

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'devtools::document(); devtools::load_all("."); testthat::test_file("tests/testthat/test-boot-select.R")'`
Expected: PASS, 10 tests.

- [ ] **Step 6: Commit**

```bash
git add R/boot-select.R R/boot-class.R man/ NAMESPACE tests/testthat/test-boot-select.R
git commit -m "feat: boot_select() resampler with valid-model retry"
```

---

### Task 4: `boot_summary()` - the parity-tested core

**Files:**
- Create: `R/boot-summary.R`, `tests/testthat/helper-fixtures.R`, `tests/testthat/test-boot-summary.R`

**Interfaces:**
- Consumes: `boot_selection$coefficients` from Task 3 - a numeric matrix with `NA` for unselected terms.
- Produces: `boot_summary(x)` returning a data frame with one row per term and columns `variable`, `n`, `pct`, `mean`, `sd`, `min`, `max`, sorted by descending `n`. Task 5's `boot_clusters()` consumes it.

**This is the one exactly parity-tested function.** `%SUMBOOT` runs `proc means n mean std min max`, transposes, computes `PCT = 100*N/&DS_SIZE` where `DS_SIZE` is the number of rows in its input (the replicate table), and sorts by descending `n`. All five statistics ignore missing values, which R matches with `na.rm = TRUE`. SAS `std` is the sample standard deviation, the same as R's `sd()`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/helper-fixtures.R`:

```r
# A fixed replicate table with hand-computable answers. Synthetic: no cohort
# data enters this package.
#
#        x1   x2   x3
#   r1  1.0  2.0   NA
#   r2  2.0   NA   NA
#   r3  3.0  4.0   NA
#   r4  4.0   NA   NA
#
# x1: n=4 pct=100 mean=2.5 sd=sd(1:4) min=1 max=4
# x2: n=2 pct=50  mean=3   sd=sd(c(2,4)) min=2 max=4
# x3: n=0 pct=0   mean/sd/min/max all NA
fx_replicates <- function() {
  matrix(
    c(1, 2, 3, 4,
      2, NA, 4, NA,
      NA, NA, NA, NA),
    nrow = 4,
    dimnames = list(NULL, c("x1", "x2", "x3"))
  )
}
```

Create `tests/testthat/test-boot-summary.R`:

```r
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
```

- [ ] **Step 2: Run it and watch it fail**

Run: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-boot-summary.R")'`
Expected: FAIL  -  `could not find function "boot_summary"`.

- [ ] **Step 3: Write the implementation**

Create `R/boot-summary.R`:

```r
#' Summarise bootstrap replicates into selection frequencies
#'
#' For each candidate term, how often it was selected across replicates and the
#' distribution of its coefficient when it was. The R port of `%SUMBOOT`
#' (`~/Documents/macro.library/bootstrap.summary.sas`).
#'
#' `n` counts replicates in which the term was selected, because [boot_select()]
#' leaves an unselected term `NA`. `pct` is `100 * n / n_rep` - the denominator
#' is the replicate count, so `pct` reads as a selection frequency.
#'
#' This function is held to **exact parity** with `%SUMBOOT`: given the same
#' replicate table it must produce the same `n`, `pct`, `mean`, `sd`, `min` and
#' `max`. Resampling and model fitting are not parity-tested; see the package's
#' design spec.
#'
#' @param x A `boot_selection` from [boot_select()], or a numeric matrix with
#'   one row per replicate and one column per term.
#' @return A data frame with columns `variable`, `n`, `pct`, `mean`, `sd`,
#'   `min`, `max`, sorted by descending `n`.
#' @export
boot_summary <- function(x) {
  m <- if (inherits(x, "boot_selection")) x$coefficients else x
  if (!is.matrix(m) || !is.numeric(m))
    stop("`x` must be a boot_selection object or a numeric matrix.",
         call. = FALSE)

  n_rep <- nrow(m)
  stat <- function(f, col) {
    v <- col[!is.na(col)]
    if (length(v) == 0L) return(NA_real_)
    f(v)
  }
  out <- data.frame(
    variable = colnames(m),
    n    = as.integer(colSums(!is.na(m))),
    pct  = 100 * colSums(!is.na(m)) / n_rep,
    mean = vapply(seq_len(ncol(m)), function(j) stat(mean, m[, j]), numeric(1)),
    sd   = vapply(seq_len(ncol(m)), function(j) stat(stats::sd, m[, j]), numeric(1)),
    min  = vapply(seq_len(ncol(m)), function(j) stat(min, m[, j]), numeric(1)),
    max  = vapply(seq_len(ncol(m)), function(j) stat(max, m[, j]), numeric(1)),
    stringsAsFactors = FALSE
  )
  out <- out[order(-out$n, out$variable), , drop = FALSE]
  rownames(out) <- NULL
  out
}
```

- [ ] **Step 4: Run the tests**

Run: `Rscript -e 'devtools::document(); devtools::load_all("."); testthat::test_file("tests/testthat/test-boot-summary.R")'`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add R/boot-summary.R man/ NAMESPACE tests/testthat/helper-fixtures.R tests/testthat/test-boot-summary.R
git commit -m "feat: boot_summary(), the parity-tested %SUMBOOT port"
```

---

### Task 5: `boot_clusters()` - cluster-aware aggregation

**Files:**
- Create: `R/boot-clusters.R`, `tests/testthat/test-boot-clusters.R`
- Modify: `tests/testthat/helper-fixtures.R`

**Interfaces:**
- Consumes: `boot_selection$coefficients` from Task 3.
- Produces: `boot_clusters(x, clusters)` where `clusters` is a named list mapping a cluster name to its member terms. Returns a data frame with `cluster`, `n_any`, `pct_any`, and a nested-friendly `members` character column.

**Read `~/Documents/macro.library/bootstrap.clusters.sas` before implementing.** Its purpose comment: *"look for variables in a list of highly correlated variables (a cluster) and determine 1) how often each variable appeared, and 2) how often at least one variable in the cluster appears."* Per-variable frequency is already `boot_summary()`; this function adds the **at least one** count, which is not derivable from the per-variable numbers - two members selected in the same replicate count once.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/helper-fixtures.R`:

```r
# Replicate table where cluster membership matters:
#
#        a1   a2   b1
#   r1  1.0   NA  1.0
#   r2   NA  1.0  1.0
#   r3  1.0  1.0   NA
#   r4   NA   NA   NA
#
# cluster A = {a1, a2}: a1 selected twice, a2 twice, but "at least one of A"
# happens in r1, r2, r3 = 3 replicates, NOT 4. That is the number the
# per-variable summary cannot give you.
fx_cluster_replicates <- function() {
  matrix(
    c(1, NA, 1, NA,
      NA, 1, 1, NA,
      1, 1, NA, NA),
    nrow = 4,
    dimnames = list(NULL, c("a1", "a2", "b1"))
  )
}
```

Create `tests/testthat/test-boot-clusters.R`:

```r
test_that("n_any counts replicates with at least one member, not the sum", {
  out <- boot_clusters(fx_cluster_replicates(),
                       list(A = c("a1", "a2"), B = "b1"))
  a <- out[out$cluster == "A", ]
  # a1 appears twice and a2 twice, but they overlap in r3, so "at least one"
  # is 3 -- summing the per-variable counts would wrongly give 4.
  expect_equal(a$n_any, 3L)
  expect_equal(a$pct_any, 75)
})

test_that("a single-member cluster matches that variable's own count", {
  out <- boot_clusters(fx_cluster_replicates(),
                       list(A = c("a1", "a2"), B = "b1"))
  b <- out[out$cluster == "B", ]
  expect_equal(b$n_any, 2L)
  expect_equal(b$pct_any, 50)
})

test_that("members are reported so a reader can see what the cluster held", {
  out <- boot_clusters(fx_cluster_replicates(), list(A = c("a1", "a2")))
  expect_equal(out$members, "a1, a2")
})

test_that("a cluster naming an unknown term errors rather than silently ignoring it", {
  expect_error(
    boot_clusters(fx_cluster_replicates(), list(A = c("a1", "nope"))),
    "cluster `A` names terms not present in the replicates: nope",
    fixed = TRUE
  )
})

test_that("clusters must be a named list", {
  expect_error(
    boot_clusters(fx_cluster_replicates(), list(c("a1", "a2"))),
    "`clusters` must be a named list", fixed = TRUE
  )
})
```

- [ ] **Step 2: Run it and watch it fail**

Run: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-boot-clusters.R")'`
Expected: FAIL  -  `could not find function "boot_clusters"`.

- [ ] **Step 3: Write the implementation**

Create `R/boot-clusters.R`:

```r
#' Aggregate selection frequencies over clusters of correlated variables
#'
#' When several candidate terms measure the same thing - weight and body surface
#' area, say - each one's individual selection frequency understates the
#' cluster's importance, because replicates split between them. This reports how
#' often **at least one** member of a cluster was selected. The R port of
#' `%cluster` (`~/Documents/macro.library/bootstrap.clusters.sas`).
#'
#' `n_any` is not the sum of the members' individual counts: a replicate that
#' selected two members counts once.
#'
#' @param x A `boot_selection` from [boot_select()], or a numeric matrix with
#'   one row per replicate and one column per term.
#' @param clusters Named list mapping a cluster name to its member terms.
#' @return A data frame with columns `cluster`, `n_any`, `pct_any`, `members`,
#'   sorted by descending `n_any`.
#' @seealso [boot_summary()] for the per-variable frequencies.
#' @export
boot_clusters <- function(x, clusters) {
  m <- if (inherits(x, "boot_selection")) x$coefficients else x
  if (!is.matrix(m) || !is.numeric(m))
    stop("`x` must be a boot_selection object or a numeric matrix.",
         call. = FALSE)
  if (!is.list(clusters) || is.null(names(clusters)) || any(names(clusters) == ""))
    stop("`clusters` must be a named list.", call. = FALSE)

  for (nm in names(clusters)) {
    missing <- setdiff(clusters[[nm]], colnames(m))
    if (length(missing))
      stop("cluster `", nm, "` names terms not present in the replicates: ",
           paste(missing, collapse = ", "), ".", call. = FALSE)
  }

  n_rep <- nrow(m)
  any_hit <- vapply(clusters, function(members) {
    sub <- m[, members, drop = FALSE]
    sum(rowSums(!is.na(sub)) > 0L)
  }, integer(1))

  out <- data.frame(
    cluster = names(clusters),
    n_any   = as.integer(any_hit),
    pct_any = 100 * as.integer(any_hit) / n_rep,
    members = vapply(clusters, paste, character(1), collapse = ", "),
    stringsAsFactors = FALSE
  )
  out <- out[order(-out$n_any, out$cluster), , drop = FALSE]
  rownames(out) <- NULL
  out
}
```

- [ ] **Step 4: Run the tests**

Run: `Rscript -e 'devtools::document(); devtools::load_all("."); testthat::test_file("tests/testthat/test-boot-clusters.R")'`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add R/boot-clusters.R man/ NAMESPACE tests/testthat/helper-fixtures.R tests/testthat/test-boot-clusters.R
git commit -m "feat: boot_clusters(), the %cluster port"
```

---

### Task 6: Package documentation and the release gate

**Files:**
- Modify: `README.md`, `NEWS.md`, `R/hvtiRbootstrap-package.R`
- Create: `.github/workflows/lint.yaml`, `.github/workflows/test-coverage.yaml`

**Interfaces:**
- Consumes: every exported function from Tasks 2-5.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add a worked example to the README**

Replace the README's `## Status` section with this, keeping everything above it:

````markdown
## Example

```r
library(hvtiRbootstrap)

set.seed(1)
n  <- 300
x1 <- rnorm(n)
df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1,
                 x2 = rnorm(n), noise = rnorm(n))

fit <- boot_select(df, y ~ x1 + x2 + noise, fit_linear,
                   n_rep = 200, seed = 42)

boot_summary(fit)
#>   variable   n   pct ...      <- how often each term survived selection

boot_clusters(fit, list(size = c("x1", "x2")))
#>   cluster n_any pct_any ...   <- how often AT LEAST ONE member survived
```

`n` counts the replicates in which a term was selected, so `pct` reads as a
selection frequency. `boot_clusters()` is not the sum of its members' counts: a
replicate selecting two members counts once.

## Status

Under development. v1 covers the selection core with logistic, linear and Cox
fitters. Hazard and quantile fitters, the bootstrap-CI family, and penalised
selection are each deferred to their own spec.

## Divergence from the SAS macros

This port is **correct first, faithful second**: where the macro's behaviour and
its documented intent disagree, it implements the intent and says so here.

**D1 - `fraction` is applied.** `%bootreg` documents `FRACTION=` but never uses
it: it computes `ds_size * fraction`, prints it, and always draws `ds_size` rows.
`boot_select()` draws `round(n * fraction)`. Pass `fraction = 1` (the default) to
match SAS exactly. **A filed result run with `FRACTION` other than 1.0 was not
subsampled**, so R will disagree with it.

**D2 - stepwise selects on AIC, not p-values.** SAS `SELECTION=STEPWISE` uses
`SLE=`/`SLS=` as p-value thresholds; R's `step()` uses AIC. `sle` and `sls` are
carried for interface fidelity and do not reproduce SAS's selection term for
term. This is why model fitting sits outside the parity claim.

**D3 - the retry loop is capped.** `%bootreg` resamples until it has `RESAMPL`
valid models and never gives up, so a model that fails on every replicate spins
forever. `boot_select()` budgets `max_attempts = 10 * n_rep` and errors with a
diagnostic when it runs out. Pass `max_attempts = Inf` for the macro's
behaviour.

`boot_summary()` and `boot_clusters()` **are** held to exact parity.
````

- [ ] **Step 2: Add the package-level doc**

Replace `R/hvtiRbootstrap-package.R`:

```r
#' @keywords internal
#'
#' @details
#' Three functions do the work:
#'
#' * [boot_select()] - resample, fit, and record which terms each model kept
#'   (`%bootreg`).
#' * [boot_summary()] - per-variable selection frequency and coefficient
#'   distribution (`%SUMBOOT`).
#' * [boot_clusters()] - how often at least one member of a correlated group was
#'   selected (`%cluster`).
#'
#' Fitters are pluggable: [fit_logistic()], [fit_linear()] and [fit_cox()] ship
#' with the package, and a new model family is a new fitter rather than a new
#' pipeline.
"_PACKAGE"
```

- [ ] **Step 3: Add the remaining CI workflows**

Copy `~/Documents/GitHub/hvtiRtables/.github/workflows/lint.yaml` and
`test-coverage.yaml` unchanged - both are repo-agnostic.

- [ ] **Step 4: Run the full gate**

Run: `Rscript -e 'devtools::document(); devtools::install(quick = TRUE, upgrade = FALSE)'`
Run: `Rscript -e 'testthat::test_dir("tests/testthat")'`
Expected: PASS, 26 tests (1 + 4 + 10 + 6 + 5).

Run: `Rscript -e 'lintr::lint_package()'`
Expected: no lints. A "no visible global function" lint means the installed copy is stale - reinstall, do not add `# nolint`.

Run: `Rscript -e 'devtools::check(document = FALSE)'`
Expected: 0 errors, 0 warnings, at most the "New submission" NOTE.

- [ ] **Step 5: Commit and open the PR**

```bash
git add -A
git commit -m "docs: worked example, package overview, and the SAS divergence note"
git push -u origin <branch>
gh pr create --title "feat: hvtiRbootstrap v1 selection core" --body "$(cat <<'EOF'
Implements `docs/plans/2026-08-14-selection-core.md` against
`docs/specs/2026-08-14-hvtirbootstrap-design.md`.

Ports `%bootreg`, `%SUMBOOT` and `%cluster`: `boot_select()` resamples and fits,
`boot_summary()` turns replicate coefficients into selection frequencies, and
`boot_clusters()` reports how often at least one member of a correlated group
survived.

**The hinge:** a term the model did not select is `NA` in that replicate's row,
so counting non-missing values per column gives the selection frequency
directly. That is how the SAS macros work and the port preserves it.

**Parity** is exact for `boot_summary()` and `boot_clusters()`, tested against
hand-computed synthetic fixtures. Resampling and fitting are not parity-tested -
the first is stochastic, the second belongs to `glm`/`lm`/`coxph`.

**One deliberate divergence:** `fraction` is applied. `%bootreg` documents
`FRACTION=` but never uses it. Documented in the README and asserted in a test
so it cannot become accidental. Revert is a one-line change if any filed result
depended on the macro's actual behaviour.

No cohort data; all fixtures synthetic.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

**Spec coverage.** Architecture (two cores, thin fitters)  ->  Tasks 2-5, with the CI family and hazard/quantile fitters correctly absent per the spec's Scope. Parity table  ->  Task 4 and Task 5 carry the exact standards; Tasks 2-3 document why fitting and resampling are not parity-tested. Testing section  ->  parity fixtures (Task 4, 5), property tests on the resampler (Task 3: n_rep, retry, seed), fitter contract test (Task 2), no cohort data (all fixtures synthetic). Package conventions  ->  Task 1 and Task 6. Resolved question 1 (classed object)  ->  Task 3's `boot_selection`. Resolved question 2 (variants collapse to arguments)  ->  `boot_select()`'s `sle`/`sls`/`max_steps` parameters. Resolved question 3 (reproduce first)  ->  stepwise is the only `select` method; no alternative is offered.

**Placeholder scan.** No TBDs. Every code step carries complete code. The one judgement call - `fraction` - is stated as a decision with its rationale, its test, and its revert cost, not deferred.

**Type consistency.** Fitters return `named numeric vector | NULL` in Task 2 and are consumed that way in Task 3. `boot_selection$coefficients` is a numeric matrix in Task 3 and consumed as one in Tasks 4 and 5. `boot_summary()` returns `variable/n/pct/mean/sd/min/max` in Task 4; `boot_clusters()` returns `cluster/n_any/pct_any/members` in Task 5; neither is referenced with different names elsewhere.

**Known gap, deliberate.** `select = "stepwise"` uses `stats::step()` (AIC), which cannot honour `sle`/`sls` p-value thresholds. The spec's parity table already exempts model fitting, and the roxygen and README say so plainly. Closing it would mean writing a p-value stepwise selector - a real piece of work, and a separate decision.
