# The bootstrap branches - selection and intervals

Date: 2026-09-02
Status: approved, pending implementation plan
Supersedes nothing. Continues `docs/specs/2026-08-14-hvtirbootstrap-design.md`,
whose two-family reading is confirmed here against the macro source, and one of
whose signatures is corrected.
Origin: an internal handoff note from biostats training, 2026-09-02. That note
is kept out of this repository; everything from it that bears on the design is
restated here.

No study, variable or patient identifier appears here.

## Problem

`hvtiRbootstrap` does two different jobs that share a resampling loop, and the
package does not say which is which. The distinction lives in whoever wrote the
script.

- **Selection.** Refit on each replicate, record which variables survive, report
  how often each appeared. This is what the package does today.
- **Intervals.** Resample to get a band around an estimate. Not variable
  selection at all - the replicates are a distribution, not a vote.

The 2026-08-14 spec already drew this line, and drew it correctly: *"They are
not variable selection and must not be forced into its API."* The line was then
lost in implementation. `boot_pool_chunks()` emits `ci_lower`/`ci_upper` - a
CI-shaped output computed on the selection branch. That is precisely the forcing
the original spec forbade, and it is shipped.

This spec restates the split as a property of the code rather than of the
reader, corrects what the shipped selection branch claims, and fixes the
interval branch's contract against the macro source. It ports nothing.

## What the source says

Read from `~/Documents/macro.library`: `bn.mixed.ci.continuous.sas` (`%BNMNR`),
`bn.binary.prev.ci.unique.sas` (`%BNPREV`), the five other `bn.*` files, the
four `bl_ord.*` files, and `bootstrap.models.sas` (`%bootreg`) for comparison.

**The interval branch is a genuine second resampler.** `%BNMNR`'s signature is
`(INDAT=, INMULT=, SEED=-1, FRACTION=1.0, IV_RECORD=, RESAMPL=100, OUTP=,
TEST=0, INEST=)`. That is `%bootreg`'s own vocabulary - `SEED`, `FRACTION`,
`RESAMPL` ("Number of Valid models to be generated") - and the same
`%DO %WHILE(&SAMPLE<&RESAMPL)` valid-model loop. What is *absent* is the whole
of selection: no `PROC=`, no `SELECT=`, no `SLE=`, no `SLS=`, no `FIXED=`. The
model is fixed, its starting values supplied by `INEST=`.

**It resamples clusters, not rows.** `%BNMNR` draws patients from `INDAT`,
assigns `_PTID=_COUNTER` so a patient drawn twice becomes two distinct
pseudo-patients, then joins `INMULT` to pull that patient's repeated records.
`PROC NLMIXED` then fits `random u ~ normal(0, ...) subject=_PTID`. Renumbering
is not incidental: without it the two copies would share a random effect and the
resample would understate between-patient variance.

**`FRACTION` is genuinely applied here.** `%BNMNR` sets
`&SIZE=&DS_SIZE*&FRACTION` and then draws `DO _COUNTER=1 TO &SIZE`. `%bootreg`
computes the same quantity, prints it, and draws `&DS_SIZE` anyway - the
divergence registered as D1 for `boot_select()`. On the interval branch there
is no divergence to register: the macro already does what D1 does.

**The `&regrc` contract transfers, in disguise.** `%BNMNR` counts the columns of
the reference estimate set and of the bootstrap fit's, and increments `&SAMPLE`
only when `%IF &_ON=&_BN`. A fit that returns a different parameter count is
resampled in place and not counted. Different mechanism, identical rule: a
failed replicate is redrawn and does not consume one, so `RESAMPL` counts valid
models. `%BNMNR` also assigns `%LET LOGRC=&SYSRC;` twice and never reads it.
That is dead, and should not be ported as though it were the check.

**The per-replicate result is a curve, not a coefficient vector.** `%BNMNR`
builds a thousand-point grid - 1000 steps from `log(0.002)` to `log(10)`, plus
the endpoint appended explicitly - evaluates the fitted decomposition on it, and
writes one column per replicate. Percentiles are then taken down the replicates
at each grid point independently. That is a
**pointwise** band, not a simultaneous one, and must be documented as such.

### Coverage: the macros take no level, and return two

Every interval-producing macro in the family hardcodes its percentile points.
Not one takes a coverage parameter.

| family | files | `PROC STDIZE ... PCTLPTS=` | returns |
|---|---|---|---|
| `bn.*` | 7 files, 12 call sites | `2.5 16 50 84 97.5` | `CLL_P95`, `CLL_P68`, `MN_RES`, `CLU_P68`, `CLU_P95` |
| `bl_ord.*` | 3 of 4 files | `2.5 50 97.5` | 95% and the median |

The fourth `bl_ord.*` file, `bl_ord.delta_ci.sas`, takes `PCTLPTS=50
METHOD=MEDIAN` at three call sites - a median with no interval at all.

`16` and `84` are the 68% interval - the plus-or-minus-one-standard-error band,
to two figures. So the `bn` family computes both the 95% and the 68% interval on
every run and returns both, distinguished **by column name**.

This answers the handoff's design obligation directly. The handoff asked that
coverage travel with the estimate and that renderers read it rather than assume
it. The macro library's answer is that coverage travels *in the name of the
column*, which is stronger: a renderer selects a column, so there is no field to
forget to read, and no level to mislabel.

It also disposes of the handoff's `conf` parameter, which was specified as
`conf = 0.95` validated to `(0,1)`. The motivation was a failure pattern seen
elsewhere in this corpus: a coverage level supplied as a percentage rather than
a proportion falls outside `(0,1)`, whereupon the code substitutes a default
that yields a 68% band rather than the 95% the caller asked for. The likeliest
user error returns the default answer, silently. The observation is right and
the remedy is stronger than the one proposed: **a function that takes no level
cannot have that bug.** We therefore diverge from the handoff, not from SAS.

`MN_RES` is a misnomer. It is `PCTLPTS=50` - the bootstrap **median**. It is not
a mean and it is not the original-sample estimate. The name is not inherited.

`PCTLDEF=1` is the weighted average at *x*<sub>(np)</sub>, which is R's
`stats::quantile(type = 4)`, not the `type = 7` default. How much that matters
depends on the replicate count, and the two branches sit either side of the
line. Over 2000 standard-normal samples:

| replicates | median shift of the 2.5th percentile | median change in interval width |
|---|---|---|
| 100 - the `bn` default `RESAMPL=` | 0.14 SD | +3.7% |
| 500 | 0.03 SD | +0.7% |
| 1000 - `boot_select()`'s default `n_rep` | 0.01 SD | +0.3% |

So on the interval branch, whose parity standard is exact interval arithmetic
and whose default is 100 replicates, the type is part of the contract rather
than a detail. On the selection branch at 1000 replicates it is nearly
invisible - which is why `sel_q025`/`sel_q975` below adopt `type = 4` for
consistency with the interval branch and explicitly not as a parity claim.


## Three defects in the shipped selection branch

All three are in the same pair of objects, and none is caught by anything.

**1. `ci_lower`/`ci_upper` are conditional on selection.** `boot_bag()` builds
`$boot$replicates` in long form with `NA` dropped - correctly, so that
`boot_frequencies()` does not count an unselected term as selected.
`boot_pool_chunks()` then takes `quantile(x$estimate, 0.025)` and `0.975` over
those rows, split by parameter. For a term selected in 30% of replicates that is
a percentile interval over 30% of the replicates. It is not a confidence
interval for the coefficient in any standard sense, and it is perverse in the
direction that matters: a weakly selected term yields the *narrowest*-looking
interval, because only the replicates where it fitted strongly enough to survive
contribute to it.

The statistic is not wrong to compute. `mean`, `sd`, `min` and `max` in
`%SUMBOOT` are conditional on selection in exactly the same way, and always have
been. The name is what is wrong.

**2. The two paths disagree in shape, in two ways.** `boot_bag()` sets
`$boot$summary <- boot_summary(x)`: seven columns, keyed `variable`.
`boot_pool_chunks()` builds its own: nine columns, keyed `parameter`. So a
renderer sees the quantile columns only if the run happened to be chunked, and
sees a different key column depending on the same accident. `boot_validate()`'s
own documented bag example is `summary = data.frame(parameter = ...)`, so
`boot_bag()` contradicts the validator's contract - and the validator does not
notice, because it checks only that the `summary` slot is present.

**3. The quantile type is `7`, and SAS is `PCTLDEF=1`.** Secondary to defect 1,
since the columns do not mean what their names claim regardless of type, but it
is the same fix.

Nothing inside the package reads `$boot$summary`. `boot_frequencies()` ignores
it and rebuilds from `$boot$replicates` via
`boot_summary(.replicate_matrix(bag))`. The entire blast radius is downstream
renderers - which is why unifying the shape is safe here, and why the validator
check specified below is load-bearing rather than decorative: it is the only
thing that would ever catch the shapes drifting apart again.

## Architecture

Two families. No shared public function, and no public function whose behaviour
depends on which job the caller had in mind.

```
selection:  boot_select(data, formula, fitter, ...)  -> replicate coefficients
            boot_summary(x)                          -> per-variable N, PCT, ...
            boot_clusters(summary, clusters)         -> cluster aggregation
            boot_bag() / boot_pool_chunks()          -> a screen, poolable
            boot_validate() and the reporting layer

intervals:  boot_predict_ci(data, statistic, ...)    -> estimate + named bands
```

| | selection | intervals |
|---|---|---|
| macro | `%bootreg`, `%SUMBOOT`, `%cluster` | `%BNMNR`, `%BNPREV`, `bl_ord.*` |
| entry point | `boot_select()` | `boot_predict_ci()` |
| per replicate | named coefficients, `NA` where unselected | named estimates on a grid |
| `NA` semantics | load-bearing - `NA` is the vote | none; a missing estimate is a failed replicate |
| resampling unit | row | cluster, renumbered per draw |
| `FRACTION` | D1: macro ignores it, we apply it | applied by the macro; no divergence |
| selection | `SELECT=`, `SLE=`, `SLS=` | none - the model is fixed |
| the replicates are | a vote | a distribution |

The shared piece is internal only: the `%DO %WHILE(&SAMPLE<&RESAMPL)` loop -
draw, fit, keep on success, redraw without counting on failure, cap the attempts
- which is provably the same in both macros. It becomes `.boot_resample()`,
parameterised by a draw function and a fit function. Nothing else is shared.

### Naming

`boot_predict_ci()` is the name the 2026-08-14 spec gave this entry point, and
it is kept. The estimand it describes is right: `bn` returns a predicted
quantity over a grid with a band around it.

**Its signature in that spec is wrong, and the source is what corrects it.** The
spec wrote `boot_predict_ci(model, newdata, ...)` - a wrapper that takes an
already-fitted model and produces an interval from it. `%BNMNR` does not do
that. It refits on every replicate; the resampling *is* the method. A function
taking a fitted model could not express `%BNMNR` at all. The corrected shape
takes the data and a `statistic` callback, in the same relation to it that
`boot_select()` stands to `fitter`.

That correction is recorded here rather than by editing the 2026-08-14 spec,
which stays as the record of what was decided then.

## The interval branch, specified and deferred

`boot_predict_ci()` is **specified here and deferred to its own spec for
implementation**, joining the hazard fitter, the quantile fitter (`bq`,
hvtiRbootstrap#16) and penalised selection. Deferral is deliberate: the branch
needs a cluster-resampling contract, a `statistic` callback contract, grid
handling and a second object class, and none of those is needed to fix the three
shipped defects.

The contract it must honour, from the source:

- `statistic(data, ...)` returns a **named numeric vector** of estimates for one
  replicate, or `NULL` when the replicate did not produce a usable fit. This is
  the fitter contract, minus the selection semantics: no `NA` for "not chosen",
  because nothing is being chosen. A `NULL` is redrawn and not counted, matching
  `%IF &_ON=&_BN`.
- Resampling draws **units**, not rows. The unit defaults to the row; an `id`
  argument names a clustering column, and the drawn units are renumbered so a
  unit drawn twice is two units.
- `FRACTION` is applied, with no divergence note, because the macro applies it.
- The result carries all five `bn` quantities per estimated quantity, named:
  `cll_p95`, `cll_p68`, `median`, `clu_p68`, `clu_p95`. No `conf` argument.
- Quantiles are `stats::quantile(type = 4)`.
- The band is **pointwise**, and the documentation says so.
- Its own class (`boot_intervals`) in its own file, sharing no structure with
  `boot_selection` beyond `.boot_resample()`.

### Where `bn` lives

Deliberately open, not settled by omission. The 2026-08-14 allocation assigned
the `bn` prefix to this package; the current roadmap has it in a separate,
unscheduled `bootstrap-ci` family. Either can be right, and the decision does
not have to be made before the branch is built.

What this spec does is **bound the cost of deferring it**. Because
`boot_predict_ci()` gets its own class, its own file, and shares only an
internal helper, moving it to `bootstrap-ci` later is a file move plus a
`NAMESPACE` line - not a refactor. The decision is therefore cheap in both
directions, which is the condition under which leaving it open is legitimate.

`bq` (quantile) stays out of scope: there is no quantile fitter
(hvtiRbootstrap#16).

## Changes to ship now

Scoped to the three defects. No new exports.

**Rename, on the selection branch.** `ci_lower` and `ci_upper` become
`sel_q025` and `sel_q975`, computed with `type = 4`. Roxygen documents them as
the spread of the coefficient across **the replicates that selected it** - a
selection-branch statistic, sibling to `mean`, `sd`, `min` and `max`, which are
conditional in the same way. The names deliberately do not resemble the interval
branch's `cll_p95`/`clu_p95`, so the two cannot be read as the same quantity.

**One summary shape, from both paths:**

```
parameter, n, pct, mean, sd, min, max, sel_q025, sel_q975
```

Keyed `parameter`, which is what `$boot$replicates`, `boot_health()`,
`boot_pool_chunks()` and `boot_validate()`'s documented example already use.
`boot_bag()` renames `boot_summary()`'s `variable` column on the way into the
bag and adds the two quantile columns.

`boot_summary()` itself is unchanged and keeps `variable`. It is the standalone
`%SUMBOOT` port, it is held to exact parity, and it is not a bag.

**A validator check.** `boot_validate()` gains a column check on
`$boot$summary`. Nothing in the package reads that slot, so without this check
the two constructions can drift apart again silently, exactly as they already
have.

## Parity

Extends the 2026-08-14 table; the existing rows are unchanged.

| Component | Parity standard |
|---|---|
| `boot_summary()` | **Exact**, against `%SUMBOOT`. Unchanged. |
| `boot_clusters()` | **Exact**, against `%cluster`. Unchanged. |
| Resampling | **Not parity-tested**, on either branch. Stochastic. |
| Model fitting | **Not parity-tested.** Belongs to the engine. |
| `sel_q025`/`sel_q975` | **Not parity-tested.** No `%SUMBOOT` counterpart - these are ours. `type = 4` is for consistency with the interval branch, not a parity claim. |
| `boot_predict_ci()` interval arithmetic | **Exact.** Given a fixed matrix of replicate estimates, `quantile(type = 4)` at 2.5, 16, 50, 84, 97.5 must reproduce `PROC STDIZE PCTLMTD=ORD_STAT PCTLDEF=1 PCTLPTS=2.5 16 50 84 97.5`. At 100 replicates `type = 7` fails this by ~4% of interval width, so the fixture discriminates. |

The last row is testable now, before the branch exists, and needs no cohort
data: a checked-in matrix of replicate estimates and the five percentiles SAS
returns for it is the whole oracle. That fixture should be captured while the
SAS licence is live - it expires **2026-09-29**.

## Downstream

`hvtiRtemplates` `04.02`-`04.05` render through this package's reporting layer
and read `$boot$summary`. Both changes to that slot are breaking for them:

- the key column becomes `parameter` on the bagged path, where it was
  `variable`;
- `ci_lower`/`ci_upper` become `sel_q025`/`sel_q975`.

A template reading `ci_lower` breaks loudly, which is the intended outcome: it
was reading a number that did not mean what its name said. The template floor is
`hvtiRbootstrap >= 0.9.0`; this change requires raising it.

Batch 2a Phase 3 (`bl`, `br`, `bc` as thin templates) inherits the branch shape
set out here. Note that `bl_ord.*` is on the **interval** branch, not the
selection branch, and returns the 95% pair only.

## Two refinements

Two decisions the sections above did not settle explicitly, recorded here to
match `docs/plans/2026-09-02-bootstrap-branch-split.md`, which is where they
were made.

**Refinement 1 - the validator checks three columns, not nine.**
`boot_validate()` requires `parameter`, `n` and `pct` on `$boot$summary`, not
the full nine. The nine-column agreement between `boot_bag()` and
`boot_pool_chunks()` is guaranteed by their sharing `.bag_summary()`, which is
stronger than a check; the validator's job is the defect that actually
shipped - a summary keyed `variable` where the reporting layer reads
`parameter`. Requiring nine would reject every hand-built bag, including this
package's own `fx_bag()` fixture and the example in `boot_validate()`'s
roxygen, both of which carry exactly those three.

**Refinement 2 - no version bump.** The "Definition of done" item below used to
say "patch bump", which is wrong under the convention now in force: `AGENTS.md`
says to bump when you tag, not when you merge, and
`tests/testthat/test-package.R` skips headings that carry no version precisely
so work can merge under a standing `(unreleased)` heading. `DESCRIPTION` stays
`0.9.2`.

## Definition of done

- [x] Design note written and listed in `dev/specs/README.md`
- [x] The two branches have distinct entry points, and the split is stated in
      `AGENTS.md` and the README
- [x] No `conf` argument anywhere; coverage is carried in column names
- [x] `sel_q025`/`sel_q975` renamed, `type = 4`, roxygen says conditional on
      selection
- [x] One `$boot$summary` shape from `boot_bag()` and `boot_pool_chunks()`,
      keyed `parameter`
- [x] `boot_validate()` checks the `$boot$summary` columns
- [x] `boot_predict_ci()` specified here, deferred to its own spec
- [x] `bn`'s home recorded as deliberately open, with the deferral cost bounded
- [x] Downstream impact on `04.02`-`04.05` stated
- [x] `NEWS.md` bullets under the standing `(unreleased)` heading. **No version
      bump:** `AGENTS.md` says to bump when you tag, not when you merge, and
      `tests/testthat/test-package.R` skips unversioned headings so that work
      can merge under `(unreleased)`. This line previously said "patch bump",
      which was wrong under that convention.

## Open questions

None blocking. Two to settle when the interval branch is built:

- Whether `boot_predict_ci()`'s grid is supplied by the caller or built from the
  data. `%BNMNR` hardcodes a 1001-point log-spaced grid over `log(0.002)` to
  `log(10)`, which is a study-specific choice sitting in a macro the user is
  told to edit.
- Whether `bl_ord.*`'s 95%-only output is a third shape or the `bn` five with
  the 68% pair left `NA`.
