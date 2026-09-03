# The interval branch - `boot_predict_ci()`

Date: 2026-09-02
Status: approved, pending implementation plan
Continues `dev/specs/2026-09-02-bootstrap-branches-design.md`, which specified
this branch and deferred it to a spec of its own. This is that spec.

No study, variable or patient identifier appears here.

## What this settles

The branch-split note left three things open. All three are now decided.

**`bn` lives here.** The 2026-08-14 allocation assigned the `bn` prefix to this
package; a later roadmap moved it to an unscheduled `bootstrap-ci` family; the
split note left the question deliberately open with the cost of deferral bounded
by construction. It is now closed: the interval branch is built in
`hvtiRbootstrap`, alongside the selection branch, sharing one internal
resampler and nothing else.

**There is no grid argument.** `%BNMNR` builds a thousand-point log-spaced grid
inside a macro the user is told to edit, so the grid was never the macro's
parameter either - it was the analyst's code. In R the same thing falls out for
free: `statistic()` returns a **named numeric vector**, and percentiles are
taken down the replicates for each name. Building a grid, if the caller wants
one, is the statistic's business. This is the fitter contract with the selection
semantics removed, so the package has one callback convention rather than two.

**The name stays `boot_predict_ci()`**, as the 2026-08-14 spec and its parity
table have it. The split note corrected its signature; the name is unchanged.

## Contract

```r
boot_predict_ci(data, statistic, n_rep = 1000, fraction = 1, id = NULL,
                max_attempts = 10 * n_rep, seed = NULL, ...)
```

| argument | macro | meaning |
|---|---|---|
| `data` | `INDAT=` | the frame resampled |
| `statistic` | the edited `PROC NLMIXED` block | one replicate's estimates |
| `n_rep` | `RESAMPL=` | number of **valid** replicates |
| `fraction` | `FRACTION=` | fraction of units drawn |
| `id` | the `CCFID`/`DT_SURG` join | column naming the resampling unit |
| `max_attempts` | none | budget before giving up |
| `seed` | `SEED=` | reproducibility |
| `...` | none | passed to `statistic` |

### `statistic` returns a named numeric vector, or `NULL`

Exactly the fitter contract, minus the selection semantics. `statistic(d, ...)`
receives one resampled frame and returns a named numeric vector of that
replicate's estimates, or `NULL` when the replicate did not produce a usable
fit.

**There is no `NA` semantics on this branch, and that is the whole difference.**
On the selection branch `NA` means *this replicate did not choose this term*,
and `boot_summary()` counts non-missing values down a column, so `n` is a vote
count. Here nothing is being chosen: every valid replicate estimates every
quantity. A missing estimate is therefore not a vote, it is a broken replicate,
and it is handled by returning `NULL` for the whole replicate rather than `NA`
for one entry. A `statistic` that returns `NA` for one name is returning a
number that is not a number; the implementation treats a vector containing any
`NA` or non-finite value as `NULL`, and says so.

**Names must agree across replicates.** The first valid replicate fixes the set
of names; a later replicate returning a different set is discarded like any
other failure. This is `%BNMNR`'s `%IF &_ON=&_BN` check - it compares the
parameter *count* of the bootstrap fit against the reference - made stricter,
because a count can match while the names do not, and then the percentile at
one grid point is assembled from two different quantities.

### `NULL` is redrawn and not counted

`%BNMNR` resamples in place and increments `&SAMPLE` only on a valid fit, so
`RESAMPL=` counts valid models. `boot_predict_ci()` does the same, and reports
both counts. `max_attempts` is ours, not the macro's, for the reason registered
as D3 on the selection branch: the macro's loop never terminates when every
replicate fails, which is survivable in a batch job with an operator watching
and is an undiagnosable hang under `R CMD check`. `Inf` restores the macro's
behaviour.

### Resampling draws units, and renumbers them

`id = NULL` draws rows, which is the simple case and the one `%bootreg`
does. `id = "ccfid"` draws **units**: the distinct values of that column are
sampled with replacement, and each draw's rows are pulled.

**A unit drawn twice becomes two distinct units.** `%BNMNR` assigns
`_PTID=_COUNTER` before joining the repeated records, and then fits
`random u ~ normal(0, ...) subject=_PTID`. Without the renumbering the two
copies share a random effect, and the resample understates between-unit
variance - the estimate a bootstrap exists to get right. The implementation
therefore writes a new id column rather than reusing the drawn values, and the
name of that column is `.boot_unit` so a statistic can use it as a grouping
variable. A `data` frame that already has a `.boot_unit` column is an error, not
a silent overwrite.

`fraction` multiplies the number of **units** drawn, not rows. `%BNMNR` computes
`&SIZE=&DS_SIZE*&FRACTION` from its patient-level `INDAT` and draws that many,
so this is the macro's own behaviour rather than a divergence. Note that this is
the opposite of the selection branch, where applying `fraction` at all is
registered divergence D1 because `%bootreg` computes it and then ignores it.

### Coverage is in the column name

The result's per-quantity table has exactly these columns:

```
parameter, cll_p95, cll_p68, median, clu_p68, clu_p95
```

`cll_p95` is `quantile(type = 4)` at 0.025, `cll_p68` at 0.16, `median` at 0.50,
`clu_p68` at 0.84, `clu_p95` at 0.975 - `%BNMNR`'s
`PCTLPTS=2.5 16 50 84 97.5`, in that order, with `bn`'s own column names
lowercased. **No function takes a coverage level**, here or anywhere in the
package: the macros do not either, and a function that takes no level cannot
mislabel one.

`median` is named for what it is. `%BNMNR` calls the same quantity `MN_RES`,
which reads as a mean; it is `PCTLPTS=50`. That misnomer is not inherited.

The `bl_ord.*` macros return the 95% pair and the median only. They get the same
five columns; a caller who wants `bl_ord`'s output ignores two of them. A second
output shape would buy nothing and would have to be told apart at every
call site.

### The band is pointwise

Percentiles are taken independently for each name. That is `%BNMNR`'s own
behaviour - it transposes, runs one `PROC STDIZE`, and transposes back - and it
is a pointwise band, not a simultaneous one. The roxygen says so. A reader
drawing a curve through the `cll_p95` column is looking at the pointwise 2.5th
percentile at each grid point, which is not a 95% region for the curve.

### The returned object

Class `boot_intervals`, its own file, sharing nothing with `boot_selection`
beyond the internal resampler.

| field | meaning |
|---|---|
| `estimates` | matrix, one row per valid replicate, one column per name |
| `intervals` | the six-column data frame above |
| `n_rep` | valid replicates |
| `n_attempts` | draws made, including discarded ones |
| `call` | `match.call()` |
| `control` | `fraction`, `id`, `seed`, `n_rows`, `n_units`, `n_names`, `elapsed_mins`, `package` |

`$estimates` is kept rather than only the summary because the whole point of the
branch is that the replicates are a distribution: a caller may want a different
quantity from them, and recomputing means re-running the fit.

A `print` method reports the replicate counts and the number of quantities. A
`summary` method returns `$intervals`. This mirrors `boot_selection`.

## Architecture

```
selection:  boot_select(data, formula, fitter, ...)   -> boot_selection
intervals:  boot_predict_ci(data, statistic, ...)     -> boot_intervals
shared:     .boot_resample(draw, fit, n_rep, max_attempts)   [internal]
```

`.boot_resample()` is the `%DO %WHILE(&SAMPLE<&RESAMPL)` loop, which is provably
the same in `%bootreg` and `%BNMNR`: draw, fit, keep on success, redraw without
counting on failure, stop when the attempt budget is spent. It takes a draw
function and a fit function and returns the kept results plus the attempt count.
`boot_select()` is refactored onto it so there is one loop rather than two
copies; that refactor must not change `boot_select()`'s behaviour, and its
existing tests are the check.

Nothing else is shared. In particular `.bag_summary()` is not reused: it counts
non-missing values down a column, which is the selection branch's vote count and
is meaningless here.

## Parity

| Component | Standard |
|---|---|
| Interval arithmetic | **Exact.** `quantile(type = 4)` at 2.5, 16, 50, 84, 97.5 must reproduce `PROC STDIZE PCTLMTD=ORD_STAT PCTLDEF=1 PCTLPTS=2.5 16 50 84 97.5`. The oracle is `tests/testthat/fixtures/bn-percentile-*.csv`. |
| Resampling | **Not parity-tested.** Stochastic, on both branches. |
| The statistic | **Not parity-tested.** It is the caller's model, not ours. |
| Unit renumbering | **Behavioural, not parity.** Tested directly: a unit drawn twice must yield two distinct `.boot_unit` values. |

## Divergences to register

- **`n_rep` defaults to 1000, where `%BNMNR` defaults `RESAMPL=100`.** Chosen
  for consistency with `boot_select()` in the same package, and because a
  hundred replicates puts the 2.5th percentile on the third order statistic,
  where it is visibly unstable. `n_rep = 100` reproduces the macro. This is the
  one place this branch's default does not match its macro, and it is recorded
  rather than hidden.
- **`max_attempts`**, as on the selection branch. `Inf` restores the macro.
- **A `statistic` returning any `NA` or non-finite value is treated as a failed
  replicate.** `%BNMNR` checks only the parameter count, so a fit that converged
  to a missing estimate would pass its check and land in the percentile step,
  where SAS's percentile of a column containing missing values silently uses a
  smaller denominator. Discarding is the safer reading of the same intent.

## Scope

**In:** `boot_predict_ci()`, the `boot_intervals` class with `print` and
`summary`, unit resampling with renumbering, the five named columns,
`.boot_resample()` and `boot_select()`'s refactor onto it.

**Out, each still its own change:** the hazard fitter; the quantile fitter
(`bq`, hvtiRbootstrap#16); penalised selection; pooling chunked interval runs,
which the selection branch has and this one does not yet need; and any
`bl_ord`-specific convenience wrapper.

## Definition of done

- [ ] `boot_predict_ci()` exported, documented, and in `_pkgdown.yml`'s
      reference index - the pkgdown gate fails on an export that is not
- [ ] `statistic` contract documented as the fitter contract minus `NA`
- [ ] Unit renumbering tested directly
- [ ] The five columns, `type = 4`, no coverage argument anywhere
- [ ] `.boot_resample()` shared, `boot_select()` refactored onto it with its
      existing tests unchanged and passing
- [ ] Divergences in the roxygen, marked **Divergence**
- [ ] README and `AGENTS.md` updated: the interval branch is now built
- [ ] `NEWS.md` bullets under the standing `(unreleased)` heading. No version
      bump - bump when you tag, not when you merge
- [ ] `devtools::check()` 0/0/0, `lintr::lint_package()` 0

## Open questions

None blocking. One to revisit once the branch has users: whether pooling
chunked interval runs is wanted. The selection branch needed it because a screen
over 160 candidates ran 22 minutes per phase; whether an interval run is
similarly long depends entirely on the caller's `statistic`, so there is no
evidence yet either way.
