# P-value stepwise implementation plan

> **STATUS: SHIPPED in 0.9.3. This plan is a historical record, not work to do.** Every
> step below is ticked because the work landed; the checkboxes are kept so the plan
> reads as it was executed. Do not reimplement any of it -- read `NEWS.md` under
> `# hvtiRbootstrap 0.9.3` for what actually shipped, and the source for how.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `stats::step()` in the three fitters with a p-value stepwise
that matches `SELECTION=STEPWISE`, so that `sle`/`sls` actually select and a
172-candidate screen finishes.

**Architecture:** One new internal file, `R/stepwise.R`. A driver
(`.pv_stepwise()`) alternates a forward step and a backward step from an
**intercept-only base**, as PROC does, until nothing enters or leaves. Entry and
removal p-values come from two small dispatchers whose behaviour is pinned per
model family. `.maybe_step()` in `R/fitters.R` is the only call site, and each
fitter passes the criterion its PROC uses.

**Tech Stack:** R package, roxygen2 with markdown, testthat edition 3. **No new
dependency** - `stats::anova`, `stats::drop1`, `stats::update`, `stats::vcov`
and `stats::pchisq` do all of it.

**Spec:** `dev/specs/2026-09-03-pvalue-stepwise-design.md`

## Global Constraints

- **`sle`/`sls` must genuinely select.** The whole point of
  [#32](https://github.com/ehrlinger/hvtiRbootstrap/issues/32) is that they are
  currently recorded and ignored. A test must fail if they are ignored again.
- **No new dependency.** `DESCRIPTION` is unchanged.
- **No `criterion` argument reaches `boot_select()` or any fitter's signature.**
  Each fitter pins its PROC's behaviour internally.
- **`NA` is the design on this branch.** A term the model did not select is
  `NA`, and `boot_summary()` counts non-missing down a column. Nothing here may
  weaken that. A stepwise that keeps nothing is a legitimate zero-length result,
  not a failure - see `.coefs()`'s comment in `R/fitters.R`.
- **Warnings never discard a replicate.** Only errors and logistic
  non-convergence do. The fitters' existing `suppressWarnings()` and `tryCatch`
  stay exactly as they are.
- 80-character line limit; `lintr::lint_package()` must report **zero** lints
  (`lint.yaml` sets `LINTR_ERROR_ON_LINT: true`). Watch indentation, braces and
  object names - commits on earlier branches failed all three.
- ASCII only in R source string literals.
- Done for the whole plan: `devtools::test()` passes, 0 lints, and
  `devtools::check()` 0/0/0 from a clean `git archive` export.

**Environment gotcha:** `lintr::lint_package()`'s `object_usage_linter` resolves
against the **installed** package. A stale library invents "no visible global
function definition" warnings for new internals. Run
`R CMD INSTALL . --no-docs --no-byte-compile` and re-lint.

## What the criteria actually are, verified

Checked directly in R before this plan was written. Do not re-derive; do not
substitute.

| family | enter | how | remove | how |
|---|---|---|---|---|
| `lm` | partial F | `anova(a, b, test = "F")` | partial F | `drop1(fit, test = "F")` |
| `glm` | Rao score | `anova(a, b, test = "Rao")` | Wald | coefficient block + `vcov()` |
| `coxph` | **LR - divergence** | `anova(a, b)` | Wald | coefficient block + `vcov()` |

⚠️ **`anova.coxph` silently ignores `test =`.** `Chisq`, `Rao` and `LRT` all
return the identical p-value; it is always the likelihood-ratio test. Accepting
the argument is not computing it. `PROC PHREG` enters on score, so **Cox entry
is a registered divergence**, decided 2026-09-03. `anova.glm(test = "Rao")` by
contrast computes a genuine score test - it differs from `LRT` in the fourth
digit - so logistic entry is exact.

⚠️ **Wald removal is per TERM, not per coefficient.** A factor with three levels
contributes two coefficients and `PROC` tests the whole term with a multi-df
Wald chi-square. Taking one coefficient's `Pr(>|z|)` would be wrong for every
factor in every screen. Compute it: for the term's coefficient block `b` and its
`vcov()` submatrix `V`, `W = t(b) %*% solve(V) %*% b` on `length(b)` degrees of
freedom. Map coefficients to terms with `attr(model.matrix(fit), "assign")`.

⚠️ **PROC starts from no covariates; today's code starts from all of them.**
`.maybe_step()` passes the full model to `stats::step(direction = "both")`,
which begins at the full model and drops. `SELECTION=STEPWISE` begins with an
intercept and adds. That is a second divergence underneath #32, and this
implementation fixes it: the driver builds the intercept-only base itself and
takes the caller's formula as the scope.

## File structure

| file | responsibility | change |
|---|---|---|
| `R/stepwise.R` | the p-value stepwise | **new** |
| `R/fitters.R` | the three fitters | `.maybe_step()` rewritten; each fitter pins a criterion |
| `tests/testthat/test-stepwise.R` | | **new** |
| `tests/testthat/test-fitters.R` | | extended |
| `NEWS.md`, `AGENTS.md` | | the behaviour change |

---

### Task 1: the two p-value dispatchers

**Files:**
- Create: `R/stepwise.R`
- Test: `tests/testthat/test-stepwise.R` (new)

**Interfaces:**
- Produces `.pv_enter_p(fit, term, data, criterion)` - the p-value for ADDING
  `term` to `fit`. `criterion` is `"f"`, `"rao"` or `"lr"`.
- Produces `.pv_remove_p(fit, criterion)` - a **named numeric vector** of
  p-values for REMOVING each term currently in `fit`, one entry per term label,
  never per coefficient. `criterion` is `"f"` or `"wald"`.
- Both return `NA_real_` for a term whose test cannot be computed, and never
  error on a singular fit. Task 2 and Task 3 call them.

- [x] **Step 1: Write the failing tests**

Create `tests/testthat/test-stepwise.R`:

```r
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
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "stepwise")'`

Expected: FAIL with `could not find function ".pv_enter_p"`.

- [x] **Step 3: Write the dispatchers**

Create `R/stepwise.R`:

```r
# A p-value stepwise, in the shape PROC's SELECTION=STEPWISE has.
#
# WHY NOT stats::step(). Two reasons, and they are #31 and #32. step() refits
# the whole model for every candidate in both directions at every step, which
# costs roughly the 3.7th power of the pool -- about 450 hours for a real
# 172-candidate screen at n_rep = 500. And it selects on AIC, whose penalty of
# 2 per parameter retains a term at p < 0.157, so `sle` and `sls` were recorded
# on the bag, printed by boot_provenance(), and never applied.
#
# The criteria are pinned per family by the fitter, not chosen by the caller:
# `sle` and `sls` then mean exactly what SLE= and SLS= mean in the job being
# ported. See dev/specs/2026-09-03-pvalue-stepwise-design.md.

# The p-value for ADDING one term. NA when the test cannot be computed -- a
# candidate that will not refit is one the screen skips, not a failed replicate.
.pv_enter_p <- function(fit, term, data, criterion) {
  # `data = data` is REQUIRED, not tidiness. update.default() evaluates the
  # reconstructed call in parent.frame(), and the fit's stored call names the
  # caller's own data symbol -- `d`, or whatever the replicate was called --
  # which does not exist in this frame. Without it every stepwise replicate
  # dies with "object 'd' not found". This is the same lookup-scope trap
  # .fit_in_env() documents for step(), reached by a different route.
  # ERROR ONLY, NEVER warning. A quasi-separated candidate makes glm warn
  # "fitted probabilities numerically 0 or 1" while converging to perfectly
  # usable coefficients. Catching the warning here would return NA and refuse
  # to let that term enter -- discarding precisely the candidates where a
  # predictor is strong, which is the downward bias AGENTS.md's "WARNINGS DO
  # NOT DISCARD A REPLICATE" rule exists to prevent. The fitters already wrap
  # the whole fit in suppressWarnings(); nothing here needs to catch one.
  bigger <- tryCatch(
    stats::update(fit, stats::as.formula(paste(". ~ . +", term)),
                  data = data),
    error = function(e) NULL
  )
  if (is.null(bigger)) return(NA_real_)
  tab <- tryCatch(
    switch(criterion,
           f   = stats::anova(fit, bigger, test = "F"),
           rao = stats::anova(fit, bigger, test = "Rao"),
           lr  = stats::anova(fit, bigger)),
    error = function(e) NULL
  )
  if (is.null(tab)) return(NA_real_)
  col <- grep("^(Pr|P)\\(", names(tab), value = TRUE)
  if (!length(col)) return(NA_real_)
  as.numeric(tab[[col[[1L]]]][2L])
}

# Wald chi-square for one term's whole coefficient block.
#
# PER TERM, NOT PER COEFFICIENT. A three-level factor has two coefficients and
# PROC tests the term on two degrees of freedom. Reading one coefficient's
# Pr(>|z|) is right for a numeric term and wrong for every factor, which is the
# worst kind of wrong: it looks correct in the simple case.
.pv_wald_term <- function(fit, j) {
  b <- stats::coef(fit)[j]
  v <- tryCatch(stats::vcov(fit)[j, j, drop = FALSE],
                error = function(e) NULL)
  if (is.null(v) || anyNA(b) || anyNA(v)) return(NA_real_)
  w <- tryCatch(drop(t(b) %*% solve(v) %*% b), error = function(e) NA_real_)
  if (!is.finite(w)) return(NA_real_)
  stats::pchisq(w, df = length(b), lower.tail = FALSE)
}

# One p-value per term currently in the model, named by term label.
.pv_remove_p <- function(fit, criterion) {
  labs <- attr(stats::terms(fit), "term.labels")
  if (!length(labs)) return(stats::setNames(numeric(0), character(0)))
  if (identical(criterion, "f")) {
    tab <- tryCatch(stats::drop1(fit, test = "F"), error = function(e) NULL)
    if (is.null(tab)) return(stats::setNames(rep(NA_real_, length(labs)), labs))
    col <- grep("^Pr\\(", names(tab), value = TRUE)
    out <- stats::setNames(rep(NA_real_, length(labs)), labs)
    hit <- intersect(labs, rownames(tab))
    if (length(col) && length(hit)) out[hit] <- tab[hit, col[[1L]]]
    return(out)
  }
  asg <- attr(stats::model.matrix(fit), "assign")
  p <- vapply(seq_along(labs), function(k) {
    j <- which(asg == k)
    if (!length(j)) return(NA_real_)
    .pv_wald_term(fit, j)
  }, numeric(1), USE.NAMES = FALSE)
  stats::setNames(p, labs)
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "stepwise")'`

Expected: PASS. Then lint: the code above was checked with
`lintr::lint()` before this plan was written and is clean, so any lint you see
is something you introduced.

- [x] **Step 5: Commit**

```bash
git add R/stepwise.R tests/testthat/test-stepwise.R
git commit -m "feat: p-value dispatchers for entry and removal

Partial F for lm, Rao score for glm -- both matching their PROC exactly.
Wald removal is computed per TERM as b' V^-1 b, because a three-level
factor has two coefficients and PROC tests the term on two degrees of
freedom; reading one coefficient's Pr(>|z|) looks right for numerics and
is wrong for every factor.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: the driver

**Files:**
- Modify: `R/stepwise.R` (append)
- Test: `tests/testthat/test-stepwise.R` (append)

**Interfaces:**
- Consumes `.pv_enter_p()` and `.pv_remove_p()` from Task 1.
- Produces `.pv_stepwise(fit, data, sle, sls, max_steps, enter, remove)`, where
  `fit` is the model carrying the **full candidate formula**, `enter` is `"f"`,
  `"rao"` or `"lr"` and `remove` is `"f"` or `"wald"`. Returns a fitted model.
  Task 3 calls it.

- [x] **Step 1: Write the failing tests**

Append to `tests/testthat/test-stepwise.R`:

```r
test_that(".pv_stepwise starts empty and adds, as PROC does", {
  # SELECTION=STEPWISE begins with an intercept and adds. stats::step() began
  # at the FULL model and dropped, which is a different algorithm that can
  # settle somewhere else -- a second divergence underneath #32.
  set.seed(11)
  n <- 400
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n), junk = rnorm(n))
  d$y <- 2 * d$x1 + rnorm(n)
  full <- lm(y ~ x1 + x2 + junk, d)

  got <- .pv_stepwise(full, d, sle = 0.05, sls = 0.05, max_steps = 0,
                      enter = "f", remove = "f")

  kept <- attr(stats::terms(got), "term.labels")
  expect_true("x1" %in% kept)
  expect_false("junk" %in% kept)
})

test_that("sle actually gates entry", {
  # The test #32 exists for. At sle = 0 nothing can enter, so the result is
  # the intercept-only base. If sle were ignored the screen would still pick
  # up x1, which is overwhelming here.
  set.seed(12)
  n <- 300
  d <- data.frame(x1 = rnorm(n))
  d$y <- 3 * d$x1 + rnorm(n)
  full <- lm(y ~ x1, d)

  got <- .pv_stepwise(full, d, sle = 0, sls = 0.05, max_steps = 0,
                      enter = "f", remove = "f")

  expect_length(attr(stats::terms(got), "term.labels"), 0L)
})

test_that("sls actually gates removal", {
  # sls is the level to STAY: a term leaves when its p-value EXCEEDS it. So
  # sls = 1 keeps everything and a small sls throws the weak term out. Getting
  # this backwards would be easy and would still pass a test that only ever
  # asserted "something was removed".
  #
  # sle = 1 admits every candidate, so sls is the only thing that can explain
  # what is missing at the end. Pinned separately from sle so that honouring
  # one and ignoring the other is a failure.
  set.seed(13)
  n <- 300
  d <- data.frame(x1 = rnorm(n), junk = rnorm(n))
  d$y <- 3 * d$x1 + rnorm(n)
  full <- lm(y ~ x1 + junk, d)

  loose <- .pv_stepwise(full, d, sle = 1, sls = 1, max_steps = 0,
                        enter = "f", remove = "f")
  tight <- .pv_stepwise(full, d, sle = 1, sls = 0.001, max_steps = 0,
                        enter = "f", remove = "f")

  expect_true("junk" %in% attr(stats::terms(loose), "term.labels"))
  expect_false("junk" %in% attr(stats::terms(tight), "term.labels"))
  expect_true("x1" %in% attr(stats::terms(tight), "term.labels"))
})

test_that("a term removed once does not immediately re-enter", {
  # SAS ends the screen when the term about to enter is the one just removed.
  # With sle > sls that cycle is not exotic, it is the default outcome: the
  # term clears the entry threshold, fails the stricter stay threshold, leaves,
  # and is the best candidate again. Without the guard only the step budget
  # ends it, and the answer depends on which half of the cycle it stopped on.
  set.seed(16)
  n <- 300
  d <- data.frame(x1 = rnorm(n), junk = rnorm(n))
  d$y <- 3 * d$x1 + rnorm(n)
  full <- lm(y ~ x1 + junk, d)

  t0 <- proc.time()[["elapsed"]]
  got <- .pv_stepwise(full, d, sle = 1, sls = 0.001, max_steps = 0,
                      enter = "f", remove = "f")
  elapsed <- proc.time()[["elapsed"]] - t0

  # It must settle, not spin to a 1000-step budget.
  expect_lt(elapsed, 20)
  expect_equal(attr(stats::terms(got), "term.labels"), "x1")
})

test_that(".pv_stepwise terminates and honours max_steps", {
  # A budget, as %bootreg's MAXSTEP= is. The loop must also terminate on its
  # own when nothing enters or leaves, or a screen that oscillates between two
  # terms would run until the budget rather than settling.
  set.seed(14)
  n <- 200
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n))
  d$y <- d$x1 + d$x2 + rnorm(n)
  full <- lm(y ~ x1 + x2, d)

  one <- .pv_stepwise(full, d, sle = 0.5, sls = 0.5, max_steps = 1,
                      enter = "f", remove = "f")
  expect_lte(length(attr(stats::terms(one), "term.labels")), 1L)

  settled <- .pv_stepwise(full, d, sle = 0.5, sls = 0.5, max_steps = 0,
                          enter = "f", remove = "f")
  expect_s3_class(settled, "lm")
})

test_that(".pv_stepwise drives glm and coxph, not only lm", {
  # The three fitters each hand it a different model class.
  set.seed(15)
  n <- 400
  d <- data.frame(x1 = rnorm(n), junk = rnorm(n))
  d$y <- rbinom(n, 1, plogis(1.5 * d$x1))
  g <- .pv_stepwise(glm(y ~ x1 + junk, binomial(), d), d, 0.05, 0.05, 0,
                    enter = "rao", remove = "wald")

  expect_s3_class(g, "glm")
  expect_true("x1" %in% attr(stats::terms(g), "term.labels"))

  skip_if_not_installed("survival")
  d$t <- rexp(n, exp(0.8 * d$x1))
  d$s <- rbinom(n, 1, 0.7)
  cx <- .pv_stepwise(
    survival::coxph(survival::Surv(t, s) ~ x1 + junk, d), d,
    0.05, 0.05, 0, enter = "lr", remove = "wald"
  )
  expect_s3_class(cx, "coxph")
})
```

- [x] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "stepwise")'`

Expected: FAIL, `could not find function ".pv_stepwise"`.

- [x] **Step 3: Write the driver**

Append to `R/stepwise.R`:

```r
# The driver. Alternates a forward step and a backward step from an
# INTERCEPT-ONLY base until neither moves.
#
# WHY IT STARTS EMPTY. PROC's SELECTION=STEPWISE begins with no explanatory
# variables and adds. The code this replaces handed stats::step() the FULL
# model, which begins at the full model and drops -- a different algorithm that
# can settle on a different set. That was never registered as a divergence
# because nobody noticed it under the larger AIC one.
#
# WHY forward-then-backward, every step. That is the "stepwise" in
# SELECTION=STEPWISE: a term admitted early can become redundant once a
# correlated one enters, and must be able to leave again. Forward-only is
# SELECTION=FORWARD, which is a different option.
.pv_stepwise <- function(fit, data, sle, sls, max_steps, enter, remove) {
  scope <- attr(stats::terms(fit), "term.labels")
  # `data = data` on every update(), for the reason .pv_enter_p() documents.
  current <- tryCatch(
    stats::update(fit, stats::as.formula(". ~ 1"), data = data),
    error = function(e) NULL
  )
  if (is.null(current)) return(fit)

  budget <- if (isTRUE(max_steps > 0)) as.integer(max_steps) else
    max(1000L, 10L * length(scope))
  used <- 0L

  # SAS stops when the term about to enter is the one just removed. Without
  # that guard, any screen with sle > sls oscillates -- a term enters on its
  # entry p-value, fails the stricter stay threshold, leaves, and is
  # immediately the best candidate again -- and only the step budget ends it,
  # leaving whichever half of the cycle the budget happened to stop on.
  just_removed <- NA_character_

  repeat {
    moved <- FALSE

    # Forward: the most significant candidate enters if it clears sle.
    inside <- attr(stats::terms(current), "term.labels")
    cand <- setdiff(scope, inside)
    if (length(cand) && used < budget) {
      p <- vapply(cand, function(v) .pv_enter_p(current, v, data, enter),
                  numeric(1), USE.NAMES = FALSE)
      ok <- which(!is.na(p) & p <= sle)
      if (length(ok)) {
        best <- cand[[ok[[which.min(p[ok])]]]]
        if (identical(best, just_removed)) break
        nxt <- tryCatch(
          stats::update(current,
                        stats::as.formula(paste(". ~ . +", best)),
                        data = data),
          error = function(e) NULL
        )
        if (!is.null(nxt)) {
          current <- nxt
          used <- used + 1L
          moved <- TRUE
          just_removed <- NA_character_
        }
      }
    }

    # Backward: the least significant term leaves if it fails sls.
    inside <- attr(stats::terms(current), "term.labels")
    if (length(inside) && used < budget) {
      p <- .pv_remove_p(current, remove)
      ok <- which(!is.na(p) & p > sls)
      if (length(ok)) {
        worst <- names(p)[[ok[[which.max(p[ok])]]]]
        nxt <- tryCatch(
          stats::update(current,
                        stats::as.formula(paste(". ~ . -", worst)),
                        data = data),
          error = function(e) NULL
        )
        if (!is.null(nxt)) {
          current <- nxt
          used <- used + 1L
          moved <- TRUE
          just_removed <- worst
        }
      }
    }

    if (!moved || used >= budget) break
  }
  current
}
```

- [x] **Step 4: Run to verify they pass, then the whole suite**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "stepwise")'`
Then: `Rscript -e 'devtools::test()'` - 0 failures.

- [x] **Step 5: Commit**

```bash
git add R/stepwise.R tests/testthat/test-stepwise.R
git commit -m "feat: the stepwise driver, starting empty as PROC does

Alternates forward and backward from an intercept-only base until neither
moves. The code this replaces handed stats::step() the full model, which
starts there and drops -- a different algorithm that can settle on a
different set, and a divergence nobody had registered because the larger
AIC one hid it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: wire it into the fitters

**Files:**
- Modify: `R/fitters.R` - `.maybe_step()` and the three fitters
- Test: `tests/testthat/test-fitters.R` (append)

**Interfaces:**
- Consumes `.pv_stepwise()`.
- `.maybe_step(fit, select, data, enter, remove)` gains the two criterion
  arguments. Each fitter passes its own and nothing else changes about them.

- [x] **Step 1: Write the failing tests**

Append to `tests/testthat/test-fitters.R`:

```r
test_that("sle reaches the screen, which #32 says it did not", {
  # The regression test for #32. sle = 0 admits nothing, so every replicate
  # keeps only the intercept and no candidate can show a selection frequency.
  set.seed(21)
  n <- 200
  df <- data.frame(x1 = rnorm(n), x2 = rnorm(n))
  df$y <- 3 * df$x1 + rnorm(n)

  fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_rep = 10, sle = 0,
                     seed = 1)
  s <- boot_summary(fit)

  expect_equal(s$n[s$variable == "x1"], 0L)
  expect_equal(s$n[s$variable == "x2"], 0L)
})

test_that("a strong predictor is selected when sle admits it", {
  # The other side of the same test: with an ordinary sle the screen must
  # still find an overwhelming predictor, or the first test would pass
  # against an implementation that selects nothing ever.
  set.seed(22)
  n <- 200
  df <- data.frame(x1 = rnorm(n), x2 = rnorm(n))
  df$y <- 3 * df$x1 + rnorm(n)

  fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_rep = 20, sle = 0.10,
                     sls = 0.05, seed = 2)
  s <- boot_summary(fit)

  expect_gt(s$pct[s$variable == "x1"], 90)
})

test_that("select = 'none' still fits the full model", {
  # Unchanged behaviour, pinned so the rewrite cannot break the branch that
  # does not select at all.
  set.seed(23)
  n <- 120
  df <- data.frame(x1 = rnorm(n), x2 = rnorm(n))
  df$y <- df$x1 + rnorm(n)

  fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_rep = 5,
                     select = "none", seed = 3)

  expect_true(all(c("x1", "x2") %in% colnames(fit$coefficients)))
  expect_false(anyNA(fit$coefficients))
})
```

- [x] **Step 2: Run to verify the first test fails**

Run: `Rscript -e 'devtools::load_all("."); devtools::test(filter = "fitters")'`

Expected: the `sle = 0` test FAILS - today `sle` is ignored, so `x1` is
selected in every replicate.

- [x] **Step 3: Rewrite `.maybe_step()`**

In `R/fitters.R`, replace `.maybe_step()` entirely:

```r
# The single site where selection happens. `enter` and `remove` are pinned by
# the caller, never by boot_select()'s user: SLE= and SLS= then mean what they
# mean in the job being ported. See R/stepwise.R.
.maybe_step <- function(fit, select, data, enter, remove) {
  if (!identical(select$method, "stepwise")) return(fit)
  .pv_stepwise(fit, data, sle = select$sle, sls = select$sls,
               max_steps = select$max_steps, enter = enter, remove = remove)
}
```

`.step_budget()` is now only used by `.pv_stepwise()`. **Move it to
`R/stepwise.R` or delete it and inline its rule** - the driver already carries
that arithmetic. Do not leave it in `R/fitters.R` unreferenced; `lintr` will
not complain but a dead internal is exactly the drift this package's comments
warn about. Keep its explanatory comment wherever the rule ends up.

- [x] **Step 4: Pin each fitter's criterion**

Three one-line changes in `R/fitters.R`:

```r
# fit_linear:   PROC REG      -- partial F to enter and to remove
      .coefs(.maybe_step(fit, select, data, enter = "f", remove = "f"))

# fit_logistic: PROC LOGISTIC -- score to enter, Wald to remove
      else .coefs(.maybe_step(fit, select, data, enter = "rao",
                              remove = "wald"))

# fit_cox:      PROC PHREG    -- DIVERGENCE: LR to enter, Wald to remove
      .coefs(.maybe_step(fit, select, data, enter = "lr", remove = "wald"))
```

- [x] **Step 5: Register the Cox divergence in roxygen**

In `fit_cox()`'s roxygen, add to `@details`:

```r
#' **Divergence:** `PROC PHREG SELECTION=STEPWISE` enters a term on the score
#' chi-square. R has no score test for a Cox model - `anova.coxph()` accepts
#' `test = "Rao"` but silently ignores it and always returns the
#' likelihood-ratio test - so entry here is by likelihood ratio. The two agree
#' asymptotically and differ only for a term sitting on the entry threshold, so
#' a screen will usually select the same set and may occasionally differ on a
#' borderline candidate. Removal is Wald, matching the macro.
```

Also update `@param sle,sls` on `boot_select()` in `R/boot-select.R`: they no
longer say the criteria are "carried for interface fidelity" and that
`stats::step()` selects on AIC. They now select. Read the existing text and
replace only the sentences that are now false.

- [x] **Step 6: Run everything**

```
Rscript -e 'devtools::load_all("."); devtools::test(filter = "fitters")'
Rscript -e 'devtools::test()'
Rscript -e 'devtools::document()'
Rscript -e 'l <- lintr::lint_package(); cat("TOTAL LINTS:", length(l), "\n"); print(l)'
```

⚠️ **Other tests will change.** `test-boot-select.R` and `test-boot-summary.R`
assert selection outcomes computed under AIC. Where a test breaks because the
criterion changed, that is the fix working - update the expectation and say so
in your report. Where one breaks because the shape changed, stop and report.
**Never edit a test to hide a genuine regression**: `NA` semantics, the
zero-length-selection case in `.coefs()`, and the `select = "none"` path must
all behave exactly as before.

- [x] **Step 7: Commit**

```bash
git add R/fitters.R R/stepwise.R R/boot-select.R man/ tests/
git commit -m "fix: sle and sls now select, which they never did

They were accepted, recorded on \$control, written into a bag as
slentry/slstay and printed by boot_provenance() in every bl/br/bc report
-- and never reached the screen, because stats::step() selects on AIC.
AIC retains a term at p < 0.157 where sls = 0.05 wants 1.96 standard
errors, which measured a median 32.7 points of selection frequency away
from SAS on a real screen.

Each fitter pins its PROC's criteria: partial F for REG, score-in and
Wald-out for LOGISTIC, and for PHREG a registered divergence -- R has no
score test for a Cox model, so entry is by likelihood ratio.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: prove the cost curve broke

**Files:**
- Create: `dev/bench/2026-09-03-stepwise-scaling.R`
- Test: none. This is a measurement, not an assertion.

**Interfaces:** consumes the shipped `boot_select()`. Produces a table.

#31 is a performance claim, and it is closed by a measurement or not at all.

- [x] **Step 1: Write the benchmark**

Create `dev/bench/2026-09-03-stepwise-scaling.R`:

```r
# Does the new stepwise break the pool^3.7 curve? #31 measured stats::step()
# at 0.2s per fit over 10 candidates and 188.3s over 80 -- a log-log slope of
# 3.72, extrapolating to ~54 minutes per fit at the 172 candidates a real
# screen offers, and about 450 hours at n_rep = 500.
#
# THE EXPONENT IS THE NUMBER, not any single timing: a constant-factor win
# would leave 172 candidates just as unreachable. Synthetic data only.
suppressMessages(devtools::load_all("."))

bench1 <- function(p, n = 2000, seed = 1) {
  set.seed(seed)
  d <- as.data.frame(matrix(rnorm(n * p), n, p))
  names(d) <- paste0("x", seq_len(p))
  d$y <- rbinom(n, 1, plogis(1.2 * d$x1 - 0.8 * d$x2))
  f <- stats::as.formula(paste("y ~", paste(names(d)[1:p], collapse = " + ")))
  t0 <- proc.time()[["elapsed"]]
  invisible(fit_logistic(d, f, list(method = "stepwise", sle = 0.10,
                                    sls = 0.05, max_steps = 0)))
  proc.time()[["elapsed"]] - t0
}

pools <- c(10, 20, 40, 80, 172)
secs <- vapply(pools, bench1, numeric(1))
print(data.frame(candidates = pools, seconds = round(secs, 2)))

ok <- secs > 0
slope <- stats::coef(stats::lm(log(secs[ok]) ~ log(pools[ok])))[[2]]
cat(sprintf("\nlog-log slope: %.2f  (stats::step() measured 3.72)\n", slope))
cat(sprintf("implied at n_rep = 500, 172 candidates: %.1f hours\n",
            500 * secs[length(secs)] / 3600))
```

- [x] **Step 2: Run it and record the result**

Run: `Rscript dev/bench/2026-09-03-stepwise-scaling.R`

Paste the table, the slope and the implied hours into your report. **If the
slope is not materially below 3.72, stop and report it** - the plan has not
achieved its goal and the driver needs looking at rather than the number
massaging.

- [x] **Step 3: Commit**

```bash
git add dev/bench/2026-09-03-stepwise-scaling.R
git commit -m "bench: measure the stepwise cost curve at five pool sizes

#31 is a performance claim and closes on a measurement. The exponent is
the number, not any single timing: a constant-factor win would leave 172
candidates just as unreachable.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: say what changed

**Files:**
- Modify: `NEWS.md`, `AGENTS.md`
- Modify: `dev/specs/2026-09-03-pvalue-stepwise-design.md` (its checklist)

- [x] **Step 1: `NEWS.md`**

Under the standing `# hvtiRbootstrap (unreleased)` heading, matching the
narrative voice of the bullets already there. It must say all four of these:
`sle`/`sls` now select; results change and by how much; bags across the
boundary are not comparable; and the Cox entry divergence.

```markdown
* **`sle` and `sls` now select, which they never did.** They were accepted,
  recorded on `$control`, written into a bag as `slentry`/`slstay` and printed
  by `boot_provenance()` in every `bl`/`br`/`bc` report -- and never reached
  the screen, because `stats::step()` selects on AIC. AIC retains a term at
  p < 0.157 where `sls = 0.05` asks for 1.96 standard errors. **Selection
  frequencies change, and by a lot**: measured against the SAS run of the same
  data, the old behaviour sat a median 32.7 points away. A bag produced before
  this release and one produced after are **not comparable**.
* **The screen now starts from no candidates and adds**, as
  `SELECTION=STEPWISE` does. It previously started from the full model and
  dropped, which is a different algorithm that can settle on a different set.
* **Each fitter uses its own procedure's criteria.** `fit_linear()` tests
  partial F, `fit_logistic()` enters on the score chi-square and removes on
  Wald. **Divergence:** `fit_cox()` enters on the likelihood ratio, because R
  has no score test for a Cox model -- `anova.coxph()` accepts `test = "Rao"`
  and silently ignores it. Removal is Wald, matching `PROC PHREG`.
* No function gained a `criterion` argument, and none will: `sle` and `sls`
  mean what `SLE=` and `SLS=` mean in the job being ported.
```

- [x] **Step 2: `AGENTS.md`**

Read the "Rules for this repo" list, then add one bullet in its voice:

```markdown
- **`sle`/`sls` are live, and each fitter pins its own criteria.**
  `fit_linear()` is partial F, `fit_logistic()` is score-in and Wald-out,
  `fit_cox()` is
  LR-in and Wald-out. The LR is a registered divergence: `anova.coxph()`
  accepts `test = "Rao"` and silently ignores it, always returning the
  likelihood-ratio test, so there is no score test to call. **Do not add a
  `criterion` argument.** Under AIC, `sle` and `sls` go inert again, which is
  the defect [#32](https://github.com/ehrlinger/hvtiRbootstrap/issues/32) was
  filed for.
```

- [x] **Step 3: Tick the spec's checklist** in
`dev/specs/2026-09-03-pvalue-stepwise-design.md` for what Tasks 1-4 delivered.
Leave the parity items unticked - the production harvest is not in this plan.

- [x] **Step 4: Full release gate**

```
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test()'
Rscript -e 'l <- lintr::lint_package(); cat("TOTAL LINTS:", length(l), "\n"); print(l)'
```

Then `R CMD check` from a clean export, never the working tree:

```bash
D=$(mktemp -d) && mkdir -p "$D/pkg" && git archive HEAD | tar -x -C "$D/pkg"
cd "$D" && R CMD build pkg && R CMD check --no-manual hvtiRbootstrap_*.tar.gz
```

Expected 0 errors / 0 warnings / 0 notes.

- [x] **Step 5: Commit and stop**

```bash
git add NEWS.md AGENTS.md dev/specs/2026-09-03-pvalue-stepwise-design.md man/
git commit -m "docs: sle and sls select now, and results change

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Do **not** push and do **not** open a pull request; the controller handles that.

---

## What this plan does not do

- **No production parity harvest.** The spec calls for comparing against saved
  `%SUMBOOT` listings from the 471 production `bl`/`br`/`bc` jobs. That needs
  study data, belongs in the study repo under the PHI rule, and is its own
  change. This plan ships the algorithm and the synthetic tests.
- **No `force_in`/`force_out`.** `%bootreg`'s `INCLUDE=`/`FIXED=` have no
  `boot_select()` argument today and gain none here.
- **No `max_move`.** `hzr_stepwise()` exposes it; `%bootreg` has no equivalent.
- **No hazard fitter, quantile fitter, or penalised selection.** Each is still
  its own change.
- **No version bump.** Bump when you tag, not when you merge.
