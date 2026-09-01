# The resampling contract - what a bootstrap replicate loop owes SAS

Date: 2026-09-01
Status: proposed
Issue: [#9](https://github.com/ehrlinger/hvtiRbootstrap/issues/9)

## Problem

Two packages in this ecosystem resample and refit:

- `hvtiRbootstrap::boot_select()`, ported from `%bootreg`.
- `TemporalHazard::hzr_bootstrap()`, whose `scope=`-set *select-mode* does what
  `%HAZBOOT` does.

Issue #9 asks whether that is one implementation too many. It is - but not in
the way the issue assumes, and the interesting finding is not the duplication.
**The two loops have already drifted, and one of them disagrees with the macro
it ports.**

`%HAZBOOT` (`macro.library/bootstrap.hazard.sas`) redraws a failed replicate in
place and does not count it. `boot_select()` does the same. `hzr_bootstrap()`
does not: it records the failure, moves on, and then divides selection
frequencies by the *requested* replicate count. A screen asking for 500 with 30
failures reports a variable chosen in every model it fitted as **94%**, where
SAS and `boot_select()` both say **100%**.

That is a selection frequency under-reported in production output, and it is
what the duplication cost. This spec fixes it and writes down the contract that
would have caught it.

## The contract

Five clauses. Four are `%HAZBOOT`'s, with the line that says so; the fifth is
ours and is marked as such.

**C1. A failed replicate is redrawn in place and does not count.**

```sas
* Check to see if we have a model.  If not, do another sampling in its place  ;
  %IF &HAZRC=0 %THEN %DO;
  %LET SAMPLE=%EVAL(&SAMPLE+1);
```
`bootstrap.hazard.sas:157-159`. `&HAZRC` is `%bootreg`'s `&regrc` under another
name, and the idiom is identical: a non-zero return code resamples in place.
Warnings do not set it, so a warned-but-converged model is kept - the rule
`AGENTS.md` states for the fitters is the same rule here.

**C2. The requested count is a count of valid models, not of attempts.**

```sas
*   RESAMPL  = Number of valid models to generate           1000               ;
```
`bootstrap.hazard.sas:27`, and the loop that enforces it,
`%DO %WHILE(&SAMPLE<&RESAMPL);` at line 86. A `%DO %WHILE` on the valid count,
not a `%DO` over a fixed range.

**C3. Frequencies are taken over valid models.**

Follows from C2: `RESAMPL` is the denominator, and every output row carries
`RESAMPL=&SAMPLE` (lines 208-214). There is no count of attempts anywhere in
the output data sets, so nothing else *could* be the denominator.

**C4. Both counts are reported.**

```sas
%PUT Total number of resamplings was &TSAMPLES to generate &RESAMPL models.;
```
`bootstrap.hazard.sas:233`. The ratio is a diagnostic in its own right: a run
that took 4000 attempts to make 1000 models is not the same screen as one that
took 1010, even though both report 1000.

**C5. A retry budget bounds the loop. (Ours, not SAS's.)**

`%HAZBOOT` spins forever when no replicate ever fits. That is a hang with no
diagnostic under `R CMD check`, so both implementations stop after a budget and
say what they managed. This is `boot_select()`'s D3 divergence, adopted here
rather than the macro's behaviour, with `Inf` as the documented way back.

## Where each implementation stands

| clause | `boot_select()` | `hzr_bootstrap()` |
|---|---|---|
| C1 redraw, do not count | yes | **no** - counts and moves on |
| C2 requested = valid models | yes (`n_rep`) | **no** (`n_boot` is attempts) |
| C3 denominator is valid models | yes | **no** - `100 * n / n_boot` |
| C4 both counts reported | yes (`n_attempts`, `n_rep`) | **no** - no attempt count |
| C5 retry budget | yes (`max_attempts`, D3) | n/a - cannot loop, so cannot hang |

Two further differences, neither a contract clause:

- **RNG hygiene.** `boot_select()` restores the caller's stream
  (`withr::local_preserve_seed()`); `hzr_bootstrap()` leaves it modified. A
  script that seeds once at the top loses reproducibility from the first call
  onward. Not a SAS question - SAS has no caller stream to owe anything to -
  but a defect on the R side either way.
- **Draw size, when `fraction < 1`.** `%HAZBOOT` draws with
  `DO J=1 TO &SIZE` where `&SIZE=&DS_SIZE*&FRACTION`; a SAS `DO` loop with a
  fractional bound stops at the last whole value, so SAS **truncates**.
  `hzr_bootstrap()` truncates and matches it. `boot_select()` uses `round()`
  and does not. See *Recorded divergences* below - this is deliberately not
  fixed here.

## What changes

### TemporalHazard

`hzr_bootstrap()`'s replicate loop becomes a `while` on valid models, with a
retry budget, satisfying C1-C5. **Both modes**, not only select-mode.

The returned shape does not change, and this is the reason the change is small:
`n_success` becomes "always `n_boot` on success" and `n_failed` becomes
"attempts that failed", which is exactly `TSAMPLES - RESAMPL`. No field is
added or removed, and `print.hzr_bootstrap()` keeps working.

Applying it to refit-mode as well as select-mode has two consequences worth
stating plainly, because both are visible to users the CORR group does not
control:

- **Percentile CIs move.** `ci_lower`/`ci_upper` are computed over a fixed
  `n_boot` valid estimates rather than over however many happened to fit. For
  any existing user whose replicates never fail, nothing changes at all; for
  one whose replicates sometimes fail, the interval shifts. The statistical
  argument runs with the change - a percentile interval over a variable and
  unreported denominator is the odder of the two - but it is a behaviour
  change and belongs in TemporalHazard's NEWS as one.
- **In refit-mode `pct` becomes a constant 100.** A fixed formula yields every
  parameter in every model that fits, so once every replicate is valid, every
  parameter appears in all of them. The failure signal it used to carry moves
  to `n_failed`, which reports it more accurately.

Plus the RNG-hygiene fix, which is mode-independent.

### hvtiRbootstrap

Nothing in `R/`. `boot_select()` already satisfies C1-C5; that is the point of
writing the contract down rather than inventing one.

This document is the change. `AGENTS.md` gains a pointer to it, next to the
existing `NULL`-rather-than-error rule, which is C1 seen from the fitter's side.

## Testing

The oracle is the shape the design spec already mandates: a checked-in fixture,
synthetic, no PHI, no cohort data. A fitter that fails on a known subset of
draws makes all five clauses observable without any model actually being hard
to fit.

Four assertions, written on both sides against the same numbers:

1. Exactly `n_rep` valid models come out when some draws fail. (C1, C2)
2. A term selected in every valid model reports 100%, not
   `100 * n_valid / n_attempts`. (C3)
3. Attempts exceed successes, and both are readable from the result. (C4)
4. A fitter that always fails errors within the budget rather than hanging,
   and the message says how many models it managed. (C5)

Assertion 2 is the regression test for the defect this spec exists to fix. It
fails against `hzr_bootstrap()` as it stands today.

## Recorded divergences

**Draw size under `fraction < 1`.** `boot_select()` rounds, `%HAZBOOT` and
`hzr_bootstrap()` truncate. Not fixed here, and the reasoning is that it is
unreachable at the default: `fraction = 1` gives `round(n) == trunc(n) == n`,
so nothing in production differs today. It is also entangled with a divergence
already on the register - `%bootreg` computes `ds_size * fraction`, prints it,
and then draws `ds_size` regardless, so for the macro this spec's sibling ports
there is no SAS answer to match. `%HAZBOOT` is the only macro that genuinely
applies `FRACTION`, which is why it has an answer at all.

Recorded so that the next person to notice the mismatch finds a decision rather
than a bug.

## Non-goals

This spec deliberately does not:

- Add `fit_hazard()`. That remains deferred to its own spec, with
  [#2](https://github.com/ehrlinger/hvtiRbootstrap/issues/2) as its input.
- Deprecate `hzr_bootstrap()`'s select-mode, or any part of it.
- Create a dependency edge in either direction. `TemporalHazard` is
  CRAN-targeted and imports only `survival`; `hvtiRbootstrap` is
  HVTI-internal and will not be on CRAN. A hard edge from the former to the
  latter is not available, now or later.
- Change `boot_select()`'s public signature.
- Merge the two loops. That question is downstream of this one and stays open:
  two implementations that disagree about the denominator cannot be merged
  without silently changing every hazard selection frequency the group has
  produced, with no way to tell the fix from a regression. Making them agree is
  the prerequisite, whether or not merging ever happens.

## Open questions

**Does `%HAZBOOT`'s C1 hold for a non-converged model as well as a failed one?**
`&HAZRC` is set by the `PROC HAZARD` step; whether a converged-but-warned fit
leaves it zero is asserted here by analogy with `&regrc`, which `AGENTS.md`
documents directly. The analogy is strong - same library, same idiom, same
author - but it is an analogy. Reading the `PROC HAZARD` return-code
documentation would settle it, and would change nothing if it confirms the
reading.

**What does the reporting layer do with `n_attempts`?** `boot_health()` reports
`n_failed` as a fact rather than a check, on the grounds that a non-zero
failure count is not itself a fault. Once `hzr_bootstrap()` reports attempts
too, the *ratio* becomes available, and a run needing four attempts per model
is arguably a check rather than a fact. Out of scope here; noted because this
spec is what makes the question askable.
