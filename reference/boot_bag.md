# A screen the reporting layer can read

Convert a
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
result into the bag that
[`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md)
accepts and every reporting function reads.

## Usage

``` r
boot_bag(x, base_params, requested, manifest, dropped = NULL, usable = NULL)
```

## Arguments

- x:

  A `boot_selection` from
  [`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md),
  run under 0.9.2 or later. An object from an earlier version carries no
  `$control` and is refused by name rather than failing on an absent
  list element.

- base_params:

  Character. The terms that are the base model rather than candidates.
  They are excluded from every frequency, and the first of them is the
  parameter
  [`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
  watches for a zero standard deviation. Must name terms the screen
  carries. **A Cox model has no intercept**, so `"(Intercept)"` copied
  from a logistic runner names nothing and is refused.

- requested:

  Numeric. How many candidates the runner **offered**, before it dropped
  any. Not derivable here: a candidate dropped before screening never
  became a column.

- manifest:

  A named list describing the dataset screened, indexed by name.
  `list(sha256 = ...)` at minimum.

- dropped:

  Optional data frame of candidates dropped before screening, as
  [`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md)
  reports it. Absent means nothing was dropped.

- usable:

  Optional numeric, checked rather than used. Supply it to assert the
  count the runner believed it screened; a disagreement with the
  screen's own term count is refused, because one of the two is
  describing a different run.

## Value

A list carrying the fields
[`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md)
requires: `n_boot`, `seed`, `slentry`, `slstay`, `base_params`,
`requested`, `usable`, `n_rows`, `elapsed_mins`, `manifest`, `engine`,
`dropped` when supplied, and `boot` holding `replicates`, `summary`,
`n_success` and `n_failed`. Validated before it is returned, so this
function cannot emit a bag that a report will refuse three chunks into a
render.

## Details

[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
returns a **wide** object: one row per replicate, one column per term,
`NA` where a term was not selected. The reporting layer reads a **long**
one, because it was extracted from a hazard runner that writes long.
Nothing converted between them, so this package's own screen function
could not reach its own report and every study would have hand-written
the pivot plus nine provenance fields. This is that conversion, written
once.

**The pivot drops `NA` rather than writing it.** That is not an
optimisation:
[`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md)
counts a term's rows against `n_boot`, so a row written for an
unselected term would be counted as a selection and every frequency
would rise. The replicate count travels in `n_boot`, never in the row
count.

Everything the run knows about itself comes from `x$control` rather than
from an argument, so a bag cannot claim an entry level the screen did
not use. The arguments here are the facts
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
cannot know: which terms are the base model, how many candidates existed
before the runner dropped any, what dataset was screened, and what was
dropped.

## See also

[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
for the screen,
[`boot_provenance()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_provenance.md)
and
[`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md)
for what reads the result.

## Examples

``` r
set.seed(1)
n  <- 200
x1 <- rnorm(n)
df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1, x2 = rnorm(n))
fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_rep = 10, seed = 42)
bag <- boot_bag(fit, base_params = "(Intercept)", requested = 2,
                manifest = list(sha256 = "example"))
boot_frequencies(bag)
#>   variable term  n pct mc_error near_threshold retained
#> 1       x1   x1 10 100  0.00000             NA       NA
#> 2       x2   x2  3  30 14.49138             NA       NA
```
