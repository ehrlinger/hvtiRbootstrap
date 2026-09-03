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

**The stepwise is implemented here, reading `hzr_stepwise()` as prior art.**
`TemporalHazard` already has a working p-value stepwise in PROC's vocabulary,
and the first version of this spec put the generalisation there. That was
revisited on 2026-09-03 and reversed, for reasons that belong on the record:

- **`TemporalHazard` is a CRAN package, and its `Description` is a contract.**
  It promises "native R implementations of the multiphase parametric hazard
  model of Blackstone, Naftel, and Turner (1986) ... parity ... against
  reference outputs from the original 'C'/'SAS' HAZARD program". Its
  `AGENTS.md` opens with *"The package exists to reproduce a reference
  implementation."* Driving `lm`, `glm` and `coxph` is not that, and a
  partial-F criterion would be carried for models it cannot fit.
- **Its check budget has to absorb it.** `R CMD check --as-cran` is 3m 33s
  against CRAN's ~10 minute ceiling - the ceiling that archived
  ggRandomForests in June 2026 - and its contract says to watch that budget
  when adding unskipped slow tests. The stepwise already carries 2,248 lines
  of tests across ten files; a four-family matrix lands on top of those.
- **It is mid-repair.** Four of the last six commits there are stepwise
  tests, on `fix/tests-passing-over-degenerate-fits`, with
  `TemporalHazard#215` open against a stepwise test that passes over a screen
  that scored nothing. Building on it now means building on a moving target.

`hvtiRbootstrap` is internal: no `Description` to widen, no check ceiling, and
no new dependency imposed on a CRAN package. **No dependency on
`TemporalHazard` is added.**

⚠️ **The "two implementations will drift" objection is weaker than it first
looks, and the first version of this spec overstated it** by analogy to
`.boot_resample()`. That was one identical loop written twice. This is not:
hazard fits carry `theta`, `objective` and shape parameters that `lm`, `glm`
and `coxph` have no analogue for, and the degrees-of-freedom arithmetic
subtracts them. Two focused implementations are plausibly less machinery than
one adapter pretending four model families are the same shape.

**#9's answer, then:** `hzr_stepwise()` stays where it is and keeps serving
`hazard`. This package owns selection for its own fitters. Whether a future
`fit_hazard()` calls `hzr_stepwise()` rather than this one is a question for
the hazard-fitter spec, not this one - and the answer is probably yes, because
that is the model family it was written for.

## What to take from `hzr_stepwise()`, and what not to

It is the reference for this implementation even though it is not imported.
Read it before writing anything.

**Take the shape.** It is already decomposed the way this one should be -
`.hzr_stepwise_candidates`, `.hzr_stepwise_drop_candidates`,
`.hzr_stepwise_forward_step`, `.hzr_stepwise_forward_step_score`,
`.hzr_stepwise_backward_step` - and that decomposition is what makes a
forward/backward/both driver testable a step at a time. Its argument names are
PROC's, and this implementation uses the same ones so a reader moving between
the two is not learning a second vocabulary.

**Take the fixture idea.** It carries a stepwise fixture harness
(`.hzr_build_stepwise_fixture`, `.hzr_stepwise_fixture_schema`,
`.hzr_validate_stepwise_fixture`): a recorded screen, replayed and validated
against a schema. That is the right pattern for parity here too, and it is
worth copying rather than inventing.

**Do not take the fit handling.** This is where the two genuinely part. It
reads `$fit$theta`, `$fit$objective` and `$fit$converged`, calls
`.hzr_refit_blocker()` to decide whether a base fit can be refit at all, and
subtracts `.hzr_stepwise_shape_count()` from the parameter count. None of that
transfers. Here the equivalents are `coef()`, `logLik()`, `update()` and
`anova()`, which `lm`, `glm` and `coxph` all provide - verified for `lm` and
`glm` directly.

**It has no partial-F criterion.** It offers `score`, `wald` and `aic`. `PROC
REG SELECTION=STEPWISE` tests partial F, so `fit_linear()` parity needs one
written here. That is now an ordinary piece of this package's work rather than
a cost imposed on somebody else's CRAN release.

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

- The fitters call the new internal stepwise instead of `stats::step()`.
  `.maybe_step()` in `R/fitters.R` is the single site.
- **`sle` and `sls` become live.** See the next section.
- **No new dependency.** `DESCRIPTION` is unchanged; the stepwise is an
  internal here, built on `stats` generics the three fitters' engines already
  provide.
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

**In:** the stepwise itself, as an internal here - candidate enumeration, a
forward step, a backward step, and a driver over `direction`; the score, Wald
and partial-F criteria; `hvtiRbootstrap`'s three fitters switched over; `sle`
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

None blocking. Three to revisit once it is built.

**Does `fit_hazard()`, when it exists, call `hzr_stepwise()` instead?**
Probably yes: that is the model family it was written for, and the shape
arithmetic this implementation deliberately does not carry is exactly what a
hazard screen needs. That would leave the family with two stepwise
implementations serving two model families, which is the outcome this spec
accepts rather than regrets. It belongs to the hazard-fitter spec.

**Should the two converge later?** If this one proves general and the hazard
one proves reducible to it, a shared package is the obvious end state - the
third option weighed on 2026-09-03. It is not worth building before there is
evidence the abstraction holds, and there is none yet.

**Does `max_move` matter here?** `hzr_stepwise()` exposes it and `%bootreg`
has no equivalent. It is out of scope, but if a real screen turns out to cycle
between two terms without it, that is the evidence to reopen this.
