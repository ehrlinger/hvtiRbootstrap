# A p-value stepwise for the selection branch

Date: 2026-09-03
Status: approved, pending implementation plan
Closes the design question in
[#9](https://github.com/ehrlinger/hvtiRbootstrap/issues/9). Addresses
[#31](https://github.com/ehrlinger/hvtiRbootstrap/issues/31) and
[#32](https://github.com/ehrlinger/hvtiRbootstrap/issues/32), which are one
problem with one fix.

No study, variable or patient identifier appears here.

## Problem

Two issues, one cause.

**#31 - the core cannot run a real screen.** `boot_select(select = "stepwise")`
costs roughly the **3.7th power of the candidate pool**. Measured with
`fit_logistic()` on a real cohort:

| candidates | seconds per fit |
|---|---|
| 10 | 0.2 |
| 20 | 1.0 |
| 40 | 14.3 |
| 60 | 64.6 |
| 80 | 188.3 |

Extrapolated to that study's actual pool of 172, about 54 minutes per fit -
matching an observed fit still running at 39 minutes when it was killed. At
`n_rep = 500`, the figure the SAS job used, that is **roughly 450 hours**. A
172-candidate pool is ordinary here: the method depends on offering competing
transformations rather than pruning them first.

**#32 - where it does run, it answers a different question.** `sle` and `sls`
are accepted, recorded on `$control`, written into a bag as `slentry`/`slstay`,
and printed by `boot_provenance()` in every `bl`/`br`/`bc` report. They never
reach the screen. `stats::step()` selects on AIC, whose penalty of 2 per
parameter retains a term at **p < 0.157** where `sls = 0.05` requires 1.96
standard errors. Measured against the SAS run of the same data: median shift in
selection frequency **+32.7 points**, Spearman rank agreement 0.07. A reader
takes those two provenance rows as the criteria that produced the frequencies
below them. They are values the caller supplied and the screen discarded.

**The cause is the same in both.** `stats::step()` is the wrong algorithm. It
refits the whole model for every candidate in both directions at every step -
which is where the exponent comes from - and it selects on AIC, which is not
what `SLE=`/`SLS=` mean. `PROC LOGISTIC SELECTION=STEPWISE` updates a single
fit and tests p-values. Fixing the algorithm fixes the cost and the criterion
together.

## What this settles

**The stepwise lives in `TemporalHazard`.** `hzr_stepwise()` already implements
PROC's vocabulary - `direction`, `criterion`, `slentry`, `slstay`, `max_steps`,
`max_move`, `force_in`, `force_out` - and has been exercised against production
hazard screens. It is generalised there rather than reimplemented here, and
`hvtiRbootstrap` depends on it. That answers #9: **TemporalHazard owns
selection, `hvtiRbootstrap` owns resampling.** One implementation, and the
family avoids the drift that made `.boot_resample()` shared in the first place.

**The criterion is matched per family and is not a caller's argument.** `SLE=`
and `SLS=` then mean exactly what they mean in the job being ported, so a
migrated screen reproduces SAS without anyone choosing anything - the package's
stated principle that the default behaviour matches SAS.

## What generalising actually costs

⚠️ **An earlier estimate called the coupling thin on the basis of a reference
count - 16 hazard-specific mentions against 32 generic ones across 271 lines.
That count was misleading and this section replaces it.** The algorithm is not
merely gated on the class; it is written around hazard's fit object.

- `inherits(fit, "hazard")` is the gate, and the cheap part.
- `.hzr_refit_blocker(fit)` decides whether a base fit can be refit at all.
- `.hzr_aic()` and `.hzr_stepwise_shape_count()` are hazard-specific.
  **Shape parameters have no analogue in `lm`, `glm` or `coxph`**, and the
  degrees-of-freedom arithmetic subtracts them from the parameter count.
- It reads `$fit$theta`, `$fit$objective` and `$fit$converged` rather than
  `coef()`, `logLik()` and a convergence generic.
- `criterion = "score"` requires a converged base model with fitted values.

So generalisation means **introducing an adapter over "a fit"**: coefficients,
log-likelihood, degrees of freedom, a refit, and a convergence flag. `hazard`
implements it through `theta`/`objective`; `lm`, `glm` and `coxph` through
`coef()`, `logLik()`, `update()` and `anova()`, all four of which are present
and were verified. That is a real piece of design work, not a deleted `if`.

Two things make it cheaper than it sounds. The algorithm is **already
decomposed** - `.hzr_stepwise_candidates`, `.hzr_stepwise_drop_candidates`,
`.hzr_stepwise_forward_step`, `.hzr_stepwise_forward_step_score`,
`.hzr_stepwise_backward_step` - so the adapter has seams to attach to. And a
**stepwise fixture harness already exists** in that package
(`.hzr_build_stepwise_fixture`, `.hzr_stepwise_fixture_schema`,
`.hzr_validate_stepwise_fixture`), which the parity plan below reuses rather
than reinvents.

**A partial-F criterion does not exist and must be added.** `hzr_stepwise`
offers `score`, `wald` and `aic`. `PROC REG SELECTION=STEPWISE` tests partial
F, so `fit_linear()` parity requires a fourth criterion.

## The criterion, per family

| fitter | the PROC it ports | enter | remove |
|---|---|---|---|
| `fit_logistic()` | `PROC LOGISTIC` | score chi-square | Wald chi-square |
| `fit_cox()` | `PROC PHREG` | score chi-square | Wald chi-square |
| `fit_linear()` | `PROC REG` | partial F | partial F |

Neither `boot_select()` nor any fitter gains a `criterion` argument.
`hzr_stepwise()` keeps its own, because it is a general tool; the fitters pin
the value their PROC uses. A caller who wants AIC has `stats::step()` and does
not need this package to offer it.

⚠️ **The `aic` path is deliberately not reachable from `boot_select()`.** Under
AIC, `sle` and `sls` are inert, which is exactly the defect #32 describes.
Exposing it would let the fixed code reproduce the bug on request.

## What changes in `hvtiRbootstrap`

- The fitters call the generalised stepwise instead of `stats::step()`.
  `.maybe_step()` in `R/fitters.R` is the single site.
- **`sle` and `sls` become live.** See the next section.
- `DESCRIPTION` gains `TemporalHazard` in `Imports`.
- `max_steps` keeps its meaning. `%bootreg`'s `INCLUDE=` and `FIXED=` map onto
  `force_in`/`force_out`, which `boot_select()` does not currently expose; that
  is recorded, not built.
- `boot_provenance()`'s `slentry`/`slstay` rows become **true**. They are
  already printed; today they describe a criterion that was discarded.

## The behaviour change, stated plainly

**Selection frequencies will change for every existing caller**, and by a lot.
The one measurement available puts today's R output a median 32.7 points away
from SAS on the same data, so the fix moves results by about that much. A bag
produced before this change and one produced after are **not comparable**, and
nothing in a bag currently distinguishes them beyond the `package` version in
`$control`.

`NEWS.md` must say so in those terms. The version bump is the maintainer's
call, but this is the largest behavioural change the package has made.

## Parity: harvest, do not capture

⚠️ **The SAS licence runs to 2027-09.** Earlier specs said 2026-09-29, which
was wrong and was distorting priorities; corrected 2026-09-03. There is about a
year, and no reason to rush a capture.

**No new SAS runs are needed.** The `hvtiRtemplates` job census
(`dev/specs/artifacts/2026-09-02-job-census-summary.json`) counts **352 `bl`,
103 `br` and 16 `bc`** production SAS jobs, and the earlier census counted
`.lst`, `.log` and `.sas7bdat` as evidence that a job ran - so saved output
already exists across the studies tree. A saved `%SUMBOOT` listing *is* a
selection-frequency table. A saved `OUTEST` *is* the replicate matrix.

**The comparison is distributional, not replicate-by-replicate.** R and SAS
draw different bootstrap samples, so per-replicate agreement is impossible and
only the frequencies are comparable. That is the standard already in the
package's parity table, and it is the standard #32's measurement used.

**PHI keeps the two halves apart.** No cohort data enters this package.
`TemporalHazard` already set the pattern and it is followed here: the
**parsers and the synthetic fixtures ship in-package**, and the **production
parity documents live in the study's own analysis repo**, the way
`analyses/R_hazard/parity/` does for the hazard work.

Real values to target, read from `jobs/bootstrap.logistic.lmHdead` in the macro
library: `SELECTION=STEPWISE SLE=0.07 SLS=0.05`. Note `0.07`, not the `0.10`
this package defaults to.

## Performance target

Breaking the curve is the point, so it is measured rather than asserted.
Benchmark `fit_logistic()` at pools of 10, 20, 40, 80 and 172 and record the
log-log slope. A 172-candidate, 500-replicate screen must be a job that
finishes - hours, not 450 of them. The exponent, not a single timing, is the
number to report: a constant-factor win would not make 172 candidates reachable.

## Scope

**In:** the fit adapter in `TemporalHazard`; the partial-F criterion; the
`hazard` gate removed; `hvtiRbootstrap`'s three fitters switched over; `sle`
and `sls` made live; the benchmark; the parity harness with synthetic
in-package fixtures and one or two production comparisons in the study repo.

**Out, each still its own change:** `force_in`/`force_out` on `boot_select()`;
exposing `max_move`; the hazard fitter, which is #9's other half; the quantile
fitter ([#16](https://github.com/ehrlinger/hvtiRbootstrap/issues/16));
penalised selection; and harvesting more than a couple of the 471 jobs.

## Definition of done

- [ ] `hzr_stepwise()` drives `lm`, `glm` and `coxph` as well as `hazard`,
      through an adapter rather than a widened class check
- [ ] A partial-F criterion exists and is tested
- [ ] `fit_logistic()`, `fit_cox()` and `fit_linear()` each pin their PROC's
      criterion; no `criterion` argument reaches `boot_select()`
- [ ] `sle`/`sls` demonstrably change the screen, with a test that fails if
      they are ignored again
- [ ] The benchmark records the log-log slope at five pool sizes
- [ ] Distributional parity against at least one saved production `%SUMBOOT`
      listing, documented in the study repo, not here
- [ ] Synthetic in-package fixtures; no cohort data
- [ ] `NEWS.md` states that selection frequencies change and that bags across
      the boundary are not comparable
- [ ] #31 and #32 closed, #9 answered
- [ ] `devtools::check()` 0/0/0, `lintr::lint_package()` 0

## Open questions

Two, both for the maintainer rather than the implementer.

**Does `TemporalHazard` want this?** The chosen home is another package's
roadmap, and #9 is filed here rather than there. The generalisation is
substantial - an adapter layer plus a criterion its own models never use - and
that package's maintainer has to agree the boundary is right.

**The partial-F criterion is the awkward consequence of that choice.**
`TemporalHazard` has no linear models, so it would carry a criterion nothing in
it uses, purely so that `hvtiRbootstrap`'s `fit_linear()` can reproduce
`PROC REG`. That is a real cost of putting selection there, and it is recorded
rather than smoothed over. If it proves the deciding objection, the fallback is
the third option originally weighed: a small package owning nothing but
PROC-compatible stepwise selection, depended on by both.

**A dependency note, not a question.** `TemporalHazard` is not on CRAN. As an
`Imports`, it forecloses a CRAN release of `hvtiRbootstrap` unless the
dependency is later moved to `Suggests` with a fallback. This package is
internal and the two CRAN targets in the family are elsewhere, so the cost is
accepted - but it should be a decision rather than a discovery.
