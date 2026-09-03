# Band an estimate by bootstrap resampling

The R port of `%BNMNR` and `%BNPREV` (`bn.*` in the CORR macro library).
Resamples `data`, computes `statistic` on each replicate, and reports
the percentile intervals of each estimated quantity.

## Usage

``` r
boot_predict_ci(
  data,
  statistic,
  n_rep = 1000,
  fraction = 1,
  id = NULL,
  max_attempts = 10 * n_rep,
  seed = NULL,
  ...
)
```

## Arguments

- data:

  A data frame.

- statistic:

  Function of `(data, ...)` returning a named numeric vector of one
  replicate's estimates, or `NULL` if the replicate failed. `%BNMNR`
  equivalent: the `PROC NLMIXED` block.

- n_rep:

  Number of **valid** replicates (`%BNMNR` `RESAMPL=`). **Divergence:**
  the macro defaults to 100; this defaults to 1000, matching
  [`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
  in this package. A hundred replicates puts the 2.5th percentile on the
  third order statistic, where it is visibly unstable. Pass
  `n_rep = 100` to reproduce the macro.

- fraction:

  Fraction of units drawn per replicate (`%BNMNR` `FRACTION=`). Applied,
  as the macro applies it – unlike `%bootreg`, which computes it and
  then draws the full size anyway.

- id:

  Column naming the resampling unit, or `NULL` to draw rows. When given,
  units are drawn with replacement and **renumbered**, so a unit drawn
  twice becomes two distinct units; the new id is in a `.boot_unit`
  column. `%BNMNR` equivalent: the patient-level `INDAT=` joined to the
  repeated `INMULT=`.

- max_attempts:

  Budget of draws before giving up. **Divergence:** `%BNMNR` has no cap
  and never terminates when every replicate fails. Pass `Inf` to restore
  that.

- seed:

  Optional integer for reproducibility (`%BNMNR` `SEED=`).

- ...:

  Passed to `statistic`.

## Value

An object of class `boot_intervals`. `$estimates` is a matrix with one
row per valid replicate and one column per quantity; `$intervals` is the
per-quantity table with columns `parameter`, `cll_p95`, `cll_p68`,
`median`, `clu_p68`, `clu_p95`. `$control` records the run's settings.

## Details

This is the **interval** branch. It is not variable selection: nothing
is chosen, the replicates are a distribution rather than a vote, and
there is no `NA` semantics. For selection, see
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md).

`statistic` is the fitter contract with the selection semantics removed.
It takes one resampled frame and returns a **named numeric vector** of
that replicate's estimates, or `NULL` when the replicate did not fit.
The names are the quantities banded, so a caller wanting a curve
evaluates it on their own grid inside `statistic` and names the elements
– which is what the macro does too, in a `PROC NLMIXED` block the
analyst edits.

**The bands are pointwise.** Each quantity is summarised independently,
as `%BNMNR` does. A curve drawn through `cll_p95` is the 2.5th
percentile at each point, not a 95% region for the curve.

No argument sets a coverage level, here or anywhere in this package. The
macros do not take one either: they hardcode `PCTLPTS=2.5 16 50 84 97.5`
and return both bands in columns named for their coverage. Percentiles
use [`stats::quantile()`](https://rdrr.io/r/stats/quantile.html)
`type = 4`, which is SAS's `PCTLDEF=1`. A coverage-shaped name passed
through `...` (`conf`, `level`, `alpha`, `probs`, `conf.level`,
`coverage`, `ci`, `confidence`, `conf_level`) is refused with an error
rather than silently forwarded to `statistic` and ignored.

## See also

[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
for the selection branch.

## Examples

``` r
# The names of the returned vector are the quantities banded. Here, two
# summaries of the same column; in a real screen they are typically a
# fitted curve evaluated on a grid.
df <- data.frame(x = rnorm(200))
est <- function(d, ...) c(mean = mean(d$x), sd = sd(d$x))

r <- boot_predict_ci(df, est, n_rep = 100, seed = 42)
r
#> <boot_intervals>
#>   replicates: 100 valid of 100 attempts
#>   quantities: 2
#> Bands are POINTWISE 95% and 68% percentile intervals.
#> Use summary() for the per-quantity table.
summary(r)
#>   parameter    cll_p95     cll_p68     median   clu_p68   clu_p95
#> 1      mean -0.1297683 -0.02635146 0.05454932 0.1253459 0.1894147
#> 2        sd  0.8963771  0.94575338 1.00090030 1.0438476 1.0794190
```
