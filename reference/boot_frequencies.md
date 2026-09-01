# Selection frequencies, with the error they carry

How often each candidate term survived selection, and how much of that
figure is noise.

## Usage

``` r
boot_frequencies(bag, phase = NULL, threshold = NULL)
```

## Arguments

- bag:

  A bootstrap screen. Checked by
  [`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md).

- phase:

  A function mapping a term to its phase, or `NULL`. With `NULL` there
  is no phase dimension and no `phase` column. A multiphase hazard
  screen passes `function(term) sub("[.].*$", "", term)`, which reads
  `early.age` as the early phase's decision about `age`; a logistic,
  linear or Cox screen has no phases and passes nothing. The rule is
  applied one term at a time, so it need not be vectorised. `variable`
  is the term with the returned phase label stripped from its head, and
  that happens only when a separator follows it: a label that runs
  straight into an alphanumeric character is an accidental prefix, and
  the term stands unstripped rather than being silently mangled.

- threshold:

  The retention cutoff, as a percentage, or `NULL`. This is a
  **reporting** decision and not something the run recorded: `slentry`
  and `slstay` governed each replicate's stepwise fit, and neither says
  how often a variable must survive to be worth carrying forward.

## Value

A data frame with columns `variable`, `term`, `n`, `pct`, `mc_error`,
`near_threshold` and `retained`, plus `phase` when `phase` is supplied.
`term` is the name as the screen recorded it and `variable` the same
name without its phase; they are identical when there is no phase rule.
`near_threshold` marks a term within two Monte-Carlo errors of the
cutoff – retention that would not survive a rerun with different seeds –
and both it and `retained` are `NA` when no `threshold` is given,
because with no cutoff there is no retention decision to make a claim
about.

## Details

A selection frequency is an **estimate**, not a count of something
fixed. It carries Monte-Carlo error of roughly
`sqrt(p(1 - p) / n_boot)`, which at `p = 0.5` over 500 replicates is
about 2.2 percentage points – so a variable sitting within a few points
of the retention cutoff can fall on either side of it on resampling
noise alone.

`mc_error` is computed **per variable**, not once for the table. The
error is largest at `p = 0.5` and shrinks towards either end, so a
single quoted value overstates it for the variables at the top and
understates it in the middle – and the middle is where the retention
decision is being made.

`n` and `pct` come from
[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md),
which is the function held to exact parity with `%SUMBOOT`. They are not
recomputed here: a second implementation of the selection count is the
one thing this package cannot afford. What this function adds is the
error, the cutoff and the optional phase grouping.

**The base parameters are dropped.** They are in every replicate by
construction, and reporting them at 100% invites them to be read as the
screen's most reliable findings.

## See also

[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md),
which computes the counts;
[`boot_concepts()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_concepts.md)
for the same frequencies grouped by concept;
[`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md)
for the candidates that never reached a replicate at all.

## Examples

``` r
bag <- list(
  n_boot = 4L, seed = 101, slentry = 0.07, slstay = 0.05,
  base_params = "base", requested = 4L, usable = 3L, n_rows = 500L,
  elapsed_mins = 120, manifest = list(sha256 = "abc123"),
  boot = list(
    replicates = data.frame(
      replicate = c(1L, 1L, 2L, 3L, 4L),
      parameter = c("base", "early.age", "early.age", "base", "late.bmi"),
      estimate  = c(1, 0.5, 0.6, 0.9, 0.2)),
    summary = data.frame(parameter = "base", n = 2L, pct = 50),
    n_success = 4L, n_failed = 0L))

boot_frequencies(bag)
#>    variable      term n pct mc_error near_threshold retained
#> 1 early.age early.age 2  50 25.00000             NA       NA
#> 2  late.bmi  late.bmi 1  25 21.65064             NA       NA

# A multiphase screen passes its own term-splitting rule.
boot_frequencies(bag, phase = function(term) sub("[.].*$", "", term),
                 threshold = 50)
#>   phase variable      term n pct mc_error near_threshold retained
#> 1 early      age early.age 2  50 25.00000           TRUE     TRUE
#> 2  late      bmi  late.bmi 1  25 21.65064           TRUE    FALSE
```
