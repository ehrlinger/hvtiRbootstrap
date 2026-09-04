# hvtiRbootstrap

<!-- badges: start -->
[![R-CMD-check](https://github.com/ehrlinger/hvtiRbootstrap/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRbootstrap/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/ehrlinger/hvtiRbootstrap/graph/badge.svg)](https://app.codecov.io/gh/ehrlinger/hvtiRbootstrap)
[![active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/badges/latest/active.svg)
[![pkgdown](https://github.com/ehrlinger/hvtiRbootstrap/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRbootstrap/actions/workflows/pkgdown.yaml)

[![R package version](https://img.shields.io/github/r-package/v/ehrlinger/hvtiRbootstrap)](https://github.com/ehrlinger/hvtiRbootstrap)

[![lint](https://github.com/ehrlinger/hvtiRbootstrap/actions/workflows/lint.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRbootstrap/actions/workflows/lint.yaml)
<!-- badges: end -->

Bootstrap model building for the HVTI CORR group - the R port of the SAS
`%bootreg` / `%SUMBOOT` / `%cluster` macros.

Fit a model on each of many bootstrap replicates, record which variables
survive selection, and report how often each appeared.

**Status: both branches shipped, three extensions deferred.** The selection
branch is complete — `boot_select()`, `boot_summary()`, `boot_clusters()` and
the three fitters `fit_logistic()`, `fit_linear()` and `fit_cox()`, with the
pooling and reporting layers around them. The interval branch is
`boot_predict_ci()`, the port of `%BNMNR` and `%BNPREV`. What is deferred, and
why this is still 0.x: the hazard fitter, the quantile fitter
([#16](https://github.com/ehrlinger/hvtiRbootstrap/issues/16)) and penalised
selection, each held back for a design pass rather than improvised.

Know the parity scope before comparing against SAS. `boot_summary()` and
`boot_clusters()` are specified to match `%SUMBOOT` and `%cluster` exactly, and
the interval arithmetic is checked against `PROC STDIZE PCTLDEF=1` by a fixture
test. Resampling and model fitting are not parity-tested and cannot be — the
two languages draw different samples.

Destination for 31 macro-library files, assigned by the allocation map in
`hvtiRtemplates:specs/2026-08-14-macro-allocation-design.md`. Design and scope:
`docs/specs/2026-08-14-hvtirbootstrap-design.md`.

## Install

```r
remotes::install_github("ehrlinger/hvtiRbootstrap")
```

## If you already run the macros

Three macros, three functions. To run a screen, that is all there is to learn.

| SAS | R | Notes |
|---|---|---|
| `%bootreg` | `boot_select()` | `PROC=` becomes the `fitter` argument |
| `%SUMBOOT` | `boot_summary()` | parity-tested against the macro |
| `%cluster` | `boot_clusters()` | parity-tested against the macro |

The `%bootreg` arguments you know carry the same meaning:

| SAS | R |
|---|---|
| `RESAMPL=` | `n_rep` - still counts *valid* models |
| `FRACTION=` | `fraction` - but see D1 below |
| `PROC=LOGISTIC \| REG \| PHREG` | `fit_logistic` \| `fit_linear` \| `fit_cox` |
| `SELECT=` / `FIXED=1` | `select = "stepwise"` / `select = "none"` |
| `SLE=` / `SLS=` | `sle` / `sls` - but see D2 below |
| `MAXSTEP=` | `max_steps` |
| `SEED=` | `seed` |

Note that `PROC=PHREG` maps to `fit_cox()`, which is Cox proportional hazards.
The **additive hazard** family (`bootstrap.hazard*.sas`) is a different thing
and is not in v1 at all - it needs `TemporalHazard` and has its own spec. When
it lands, the per-analysis copies (`_jr`, `_p`, `101703`, `jr1`) will not become
separate functions: they differ from `bootstrap.hazard.sas` by a changed default
and a dropped selection option, so they collapse into arguments you pass.
`_tvc` is the exception, carrying genuine time-varying-covariate behaviour.

## Two branches, one resampling loop

Bootstrapping here does one of two jobs, and they are not the same job.

**Selection** - `%bootreg`, `%SUMBOOT`, `%cluster` - refits on every replicate
and counts which terms survived. The replicates are a vote, and a term the
model did not select is `NA`. That is the whole of what this package ships
today: `boot_select()`, `boot_summary()`, `boot_clusters()`, the fitters, and
the pooling and reporting layers around them.

**Intervals** - `%BNMNR`, `%BNPREV`, `bl_ord.*` - resample to put a band around
an estimate. Nothing is selected, so there is no `NA` semantics; the replicates
are a distribution. That branch ships today as `boot_predict_ci()`.

No function here takes a confidence level. The macros do not either: they
hardcode `PCTLPTS=2.5 16 50 84 97.5` and return both the 95% and the 68% band
in columns named for their coverage, so there is no level to mislabel.

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
fit
#> <boot_selection>
#>   replicates: 200 valid of 200 attempts
#>   terms:      4
#> Use boot_summary() for per-variable selection frequencies.

boot_summary(fit)
#>      variable   n   pct         mean         sd         min       max
#> 1 (Intercept) 200 100.0 -0.008863727 0.06139726 -0.15297676 0.1901373
#> 2          x1 200 100.0  2.026035162 0.06718477  1.88008851 2.2223719
#> 3          x2  57  28.5  0.094760094 0.04738065 -0.09018219 0.1573203
#> 4       noise  39  19.5  0.106355941 0.05397506 -0.10429045 0.1834056

boot_clusters(fit, list(size = c("x1", "x2")))
#>   cluster n_any pct_any members
#> 1    size   200     100  x1, x2
```

`x1` really drives `y` here, and it survives every replicate. `x2` and `noise`
carry no signal by construction, so the 20-30% they show is stepwise keeping a
useless term by chance - a reminder that a non-zero `pct` is not on its own
evidence of anything.

`n` counts the replicates in which a term was selected, so `pct` reads as a
selection frequency. `boot_clusters()` is not the sum of its members' counts: a
replicate selecting two members counts once, which is why `size` reads 100 and
not 128.5.

## Beyond the macros

Two layers have grown around that core. Neither has a macro behind it, because
a SAS batch job never needed one.

**Pooling**, for a screen too long to run in one go. A bootstrap that writes
nothing until its last replicate is unrestartable, and a real screen can be days
of compute — a run that dies at 90% yields nothing.

| function | does |
|---|---|
| `boot_pool_chunks()` | folds chunk files into one object of the same shape, refusing chunks that disagree on the data or the screen |
| `boot_chunk_files()` | finds them, in a deterministic order |
| `boot_shortfall()` | whether what you pooled is the run you launched — which nothing inside a chunk can know |

**Reporting**, for turning a finished screen into tables. Each takes an optional
`phase`, so a multiphase hazard screen and a single-phase logistic one run down
the same code path.

| function | does |
|---|---|
| `boot_validate()` | checks the screen has the shape a report reads — shapes, not just presence |
| `boot_provenance()`, `boot_seeds()` | where the screen came from, and every seed |
| `boot_frequencies()`, `boot_dropped()` | the per-term view with its Monte-Carlo error, and the candidates never screened |
| `boot_concepts()` | groups competing forms of one thing, counting a replicate that took two once |
| `boot_health()` | whether the screen ran at all — not the same question as whether it finished |

These are computation only. Nothing here renders: no `kable()`, no `ggplot2`, no
figure. A report decides what to say; this package decides what is true.

## What is checked against SAS, and what is not

| Component | Standard |
|---|---|
| `boot_summary()` | **Exact.** Same replicate table in, same `n`, `pct`, mean, std, min, max out. |
| `boot_clusters()` | **Exact.** Same appeared / at-least-one counts. |
| Resampling | Not parity-tested. Stochastic; matching SAS's RNG stream is a research project, not a port. |
| Model fitting | Not parity-tested. That belongs to `glm`, `lm` and `coxph`. |

The parity fixtures are synthetic and checked in, so nothing here needs cohort
data and no PHI enters this repo.

## Status

Under development, and at 0.9.0 rather than 1.0.0 deliberately. The selection
core, chunk pooling and the reporting layer are all in place, with logistic,
linear and Cox fitters.

The hazard and quantile fitters, and penalised selection are each deferred to
their own spec — and the hazard fitter is why this is not 1.0.0. Its
`_CP_*evnt` and `_tvc` variants encode
competing-risks and time-varying-covariate structures that deserve reading
before an API is fixed, and a 1.0.0 that then grew a whole new fitter family
would be making a promise it had not earned.

## Divergence from the SAS macros

This port is **correct first, faithful second**: where the macro's behaviour and
its documented intent disagree, it implements the intent and says so here.

**D1 - `fraction` is applied.** `%bootreg` documents `FRACTION=` but never uses
it: it computes `ds_size * fraction`, prints it, and always draws `ds_size` rows.
`boot_select()` draws `round(n * fraction)`. Pass `fraction = 1` (the default) to
match SAS exactly. **A filed result run with `FRACTION` other than 1.0 was not
subsampled**, so R will disagree with it.

**D2 - stepwise now selects on p-values, applied per family.** SAS
`SELECTION=STEPWISE` uses `SLE=`/`SLS=` as p-value thresholds; `sle` and `sls`
now mean exactly that, tested by `boot_select()`'s own p-value stepwise
(`R/stepwise.R`) rather than by `stats::step()`, which selected on AIC and
never applied them. The test is pinned per family to match the `PROC=` it
ports: `fit_linear()` tests partial F to enter and to remove, matching
`PROC REG`; `fit_logistic()` enters on the score chi-square and removes on
Wald, matching `PROC LOGISTIC`. `fit_cox()`'s own criteria are D4, below.

**D3 - the retry loop is capped.** `%bootreg` resamples until it has `RESAMPL`
valid models and never gives up, so a model that fails on every replicate spins
forever. `boot_select()` budgets `max_attempts = 10 * n_rep` and errors with a
diagnostic when it runs out. Pass `max_attempts = Inf` for the macro's
behaviour.

**D4 - `fit_cox()` enters on the likelihood ratio, not the score test.**
`PROC PHREG SELECTION=STEPWISE` enters a term on the score chi-square. R has
no score test for a Cox model - `anova.coxph()` accepts `test = "Rao"` but
silently ignores it and always returns the likelihood-ratio test - so entry
in `fit_cox()` is by likelihood ratio instead. The two agree asymptotically
and differ only for a term sitting on the entry threshold, so a screen will
usually select the same set and may occasionally differ on a borderline
candidate. Removal is Wald, matching the macro.

**D5 - the two removal tests can disagree with each other on model
hierarchy.** `fit_linear()`'s removal test (`drop1()`) respects marginality -
a main effect under an interaction is not removable. The Wald removal test
`fit_logistic()` and `fit_cox()` use tests every term independently, so
`boot_select()` can return a model with an interaction but neither of its
main effects; the forward step can likewise admit an interaction before
either main effect enters, since candidates are flat term labels rather than
a hierarchy. `PROC LOGISTIC` defaults to `HIERARCHY=SINGLE` and would not do
this. Realistic `%bootreg` candidate pools are main effects, so the case is
narrow, but it is not implemented and the two paths do not currently agree
with each other.

A warning is not a failed fit. `%bootreg` gates on `&regrc`, a return code that
SAS warnings do not set, and the fitters match that: a converged model that
merely warned - "fitted probabilities numerically 0 or 1" on a quasi-separated
replicate, say - is kept. Errors and non-convergence still cause a redraw.
