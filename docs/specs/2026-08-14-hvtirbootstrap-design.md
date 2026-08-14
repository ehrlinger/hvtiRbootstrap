# hvtiRbootstrap - design

Date: 2026-08-14
Status: approved, pending implementation plan
Allocation: `hvtiRtemplates:specs/2026-08-14-macro-allocation-design.md` assigns
31 macro-library files here (prefixes `bh`, `bl`, `bc`, `bn`, `br`, `bq`).

## Problem

The CORR bootstrap macros do model building by resampling: fit a model on each
of ~1000 bootstrap replicates, record which variables survive selection, and
report how often each appeared. Thirty-one files in `~/Documents/macro.library`
implement this. There is no R equivalent, and the institutional SAS licence
expires **2026-09-29**.

This package is their destination. This spec says what it should be; it does not
port anything.

## The 31 files are two families, not six model types

Reading the macro signatures rather than the filenames:

**Selection (20 files).** `%bootreg` (`bootstrap.models.sas`) is *already* a
model-agnostic engine: `PROC = LOGISTIC | REG | PHREG` selects the model, and
`SEED`, `RESAMPL`, `FRACTION`, `FIXED`, `SELECT`, `SLE`, `SLS`, `INCLUDE`,
`START`, `MAXSTEP`, `TEST` are shared across all of them. `%SUMBOOT`
(`bootstrap.summary.sas`, 41 lines) summarises the replicate results into per-
variable `N`, `PCT = 100*N/nreps`, mean, std, min, max. `%cluster`
(`bootstrap.clusters.sas`) aggregates that over clusters of correlated
variables: how often each variable appeared, and how often **at least one**
member of its cluster did.

**Confidence intervals (11 files).** `bn.*` and `bl_ord.*` are a different
shape. `%BNPREV` takes `INDAT`, `INMULT`, `SEED`, `FRACTION`, `IV_RECORD` - no
model statement, no `SELECT`/`SLE`. These bootstrap **predicted quantities**
(prevalences, ordinal probabilities) out of mixed models and return intervals.
They are not variable selection and must not be forced into its API.

**Most of the file count is duplication.** `bootstrap.hazard.sas` and
`bootstrap.hazard_jr.sas` differ by **8 lines of 236**; `_tvc` by 75
(time-varying covariates - a genuine variant). Seven hazard files are perhaps
two or three real behaviours. 31 files is not 31 ports.

## Architecture - two cores, thin fitters

```
selection:   boot_select(data, formula, fitter, ...) -> replicate results
             boot_summary(results)                   -> per-variable N, PCT, ...
             boot_clusters(summary, clusters)         -> cluster-aware aggregation

intervals:   boot_predict_ci(model, newdata, ...)     -> predicted quantity + CI
```

`boot_select()` mirrors `%bootreg`'s `PROC=` with a **fitter** argument rather
than one function per model family. Fitters wrap engines that already exist:
`glm` (logistic), `lm` (linear), `survival::coxph` (Cox),
`quantreg::rq` (quantile), `TemporalHazard` (hazard). A sixth model type is a
new fitter, not a new pipeline.

The alternative - one exported function per SAS macro - was rejected because
`%bootreg` shows the SAS authors already rejected it, and because it would
re-copy into R the duplication the corpus already suffers from. A thin wrapper
over `rsample`/`boot` was also rejected: its idioms do not carry `FRACTION`,
`SELECT`, `SLE`, and stepwise-selection-per-replicate is precisely the pattern
the modern R stack declines to support.

## Parity - deterministic where the logic is, honest where it is not

`%usmatchd` had a deterministic answer to reproduce to 1e-12. This does not: the
macros resample, so a SAS run does not reproduce **itself**. Parity is therefore
scoped to the part that is deterministic.

| Component | Parity standard |
|---|---|
| `boot_summary()` | **Exact.** Given a fixed table of per-replicate results, must reproduce `%SUMBOOT`'s `N`, `PCT`, mean, std, min, max. |
| `boot_clusters()` | **Exact.** Same fixed input, must reproduce the appeared/at-least-one counts. |
| Resampling | **Not parity-tested.** Stochastic; matching SAS's RNG stream is a research project and is explicitly out of scope. |
| Model fitting | **Not parity-tested.** Belongs to `glm`/`coxph`/`TemporalHazard`, not here. |
| `boot_predict_ci()` | **Exact on the interval arithmetic** given fixed replicate predictions; the predictions themselves are the model's. |

This is testable exactly where the package's own logic lives, and says so where
it does not. **A test fixture of per-replicate results, checked in, is the
parity oracle** - it needs no cohort data and therefore no PHI.

## Scope

**v1 (this spec):** the selection core - `boot_select()`, `boot_summary()`,
`boot_clusters()` - with fitters for logistic, linear and Cox, which are the
three `%bootreg` already covers and which need no external engine beyond
`survival`.

**Deferred, each its own spec:**

- The hazard fitter. Needs `TemporalHazard`, and the `_CP_*evnt` /`_tvc`
  variants encode competing-risks and time-varying-covariate structures that
  deserve reading before an API is fixed.
- The quantile fitter (`quantreg`).
- `boot_predict_ci()` and the 11-file CI family. A separate core with a separate
  API; folding it into v1 would force one of the two into the wrong shape.
- `logitlasso.sas`. Penalised selection is a different selection mechanism, not
  a fitter.

## Testing

- **Parity fixtures.** A checked-in table of per-replicate results plus the
  `%SUMBOOT` and `%cluster` output SAS produces from it. Synthetic, no PHI.
- **Property tests** on the resampler: `FRACTION = 1.0` draws n rows with
  replacement; `RESAMPL = k` yields k replicate result rows; a fitter that
  errors on a replicate drops that replicate rather than aborting the run
  (`%bootreg`'s `RESAMPL` counts *valid* models, which is a real behaviour to
  preserve).
- **Fitter contract test** applied to every fitter, so a new one cannot join
  with a different return shape.
- No cohort data in the package. Anything requiring it lives in a study repo.

## Package conventions

Follows the estate: `hvtiRbootstrap`, GPL-3, `Config/testthat/edition: 3`,
roxygen with markdown, pkgdown, and the house CI set (`R-CMD-check`, `lint`,
`pkgdown`, `test-coverage`, `check-manual`, `house-style`). Version starts at
**0.1.0**; the full release gate applies before any 1.0.0 regardless of
destination.

## Open questions

1. **Does `boot_select()` return a data frame or a classed object?** A class
   buys a `print`/`summary`/`autoplot` surface and lets `boot_summary()` refuse
   the wrong input; a bare data frame is simpler and composes with dplyr. Decide
   at planning time, when the fitter contract is concrete.
2. **Do the `_jr`/`_p`/`101703` hazard variants encode real behaviour, or are
   they abandoned copies?** 8-line diffs suggest copies, but that must be read
   rather than assumed - the corpus has already produced one file whose name
   misled about its contents.
3. **Is stepwise selection per replicate the method to carry forward, or the
   method to reproduce and then improve on?** The port should reproduce it; the
   question is whether the package should also offer a modern alternative, and
   that is a methods decision for the CORR group, not a design one.
