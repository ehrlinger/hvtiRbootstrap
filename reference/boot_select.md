# Build a model by bootstrap resampling

The R port of `%bootreg` (`bootstrap.models.sas` in the CORR macro
library). Fits `fitter` on each of `n_rep` bootstrap replicates and
records the coefficients each model kept.

## Usage

``` r
boot_select(
  data,
  formula,
  fitter,
  n_rep = 1000,
  fraction = 1,
  select = c("stepwise", "none"),
  sle = 0.1,
  sls = 0.05,
  max_steps = 0,
  max_attempts = 10 * n_rep,
  seed = NULL
)
```

## Arguments

- data:

  A data frame.

- formula:

  Model formula offering the candidate terms.

- fitter:

  A fitter such as
  [`fit_logistic()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_logistic.md),
  [`fit_linear()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_linear.md)
  or
  [`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md).
  `%bootreg` equivalent: `PROC=`.

- n_rep:

  Number of **valid** models to generate (`%bootreg` `RESAMPL=`).
  Replicates whose fit fails are redrawn and do not count, matching the
  macro's `&regrc` check.

- fraction:

  Fraction of `nrow(data)` to draw per replicate (`%bootreg`
  `FRACTION=`). **Divergence:** the macro documents this parameter but
  never applies it - it computes `ds_size * fraction`, prints it, and
  then always draws `ds_size` rows. This implementation applies it. Pass
  `fraction = 1` (the default) to match SAS behaviour exactly.

- select:

  `"stepwise"` or `"none"` (`%bootreg` `SELECT=`/`FIXED=`).

- sle, sls:

  Entry and retention criteria (`%bootreg` `SLE=`, `SLS=`). Carried for
  interface fidelity; R's
  [`stats::step()`](https://rdrr.io/r/stats/step.html) selects on AIC,
  so these do not reproduce SAS's p-value thresholds term for term.
  Model fitting is not parity-tested - see the package's design spec.

- max_steps:

  Maximum selection steps (`%bootreg` `MAXSTEP=`). `0` means no
  restriction, implemented as a budget scaled to the model - ten passes
  over the candidate terms, floored at 1000 - which no realistic model
  reaches. It is a budget rather than a truly unbounded count because
  [`stats::step()`](https://rdrr.io/r/stats/step.html) pre-allocates a
  list of that length.

- max_attempts:

  Budget of resampling attempts before giving up. **Divergence:**
  `%bootreg` has no such cap - its loop advances only on a successful
  fit, so a model that fails on every replicate never terminates. That
  is survivable in a batch job with an operator watching the log; under
  `R CMD check` it is an unbounded hang with no diagnostic. Exhausting
  the budget raises an error reporting how many valid models were
  obtained. Pass `Inf` to restore the macro's uncapped behaviour.

- seed:

  Optional integer for reproducibility.

## Value

An object of class `boot_selection`. `$coefficients` is a matrix with
one row per valid replicate and one column per candidate term, `NA`
where the term was not selected. `$control` records the run's own
settings – `method`, `sle`, `sls`, `max_steps`, `fraction`, `seed`,
`n_rows`, `n_terms`, `elapsed_mins` and the `package` version – so that
a bag builder
([`boot_bag()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_bag.md),
not yet written) can take a provenance record from the run rather than
from what a caller retypes. `$call` cannot serve that purpose:
[`match.call()`](https://rdrr.io/r/base/match.call.html) omits every
argument left at its default.

## Details

A term the model did not select is `NA` in that replicate's row. That
missingness is the whole design:
[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
counts non-missing values down a column, so `n` *is* the number of
replicates that chose the term. Do not fill those gaps with zero.

`fitter` is what `PROC=` was. Adding a model family means writing a
fitter, not another pipeline.

## See also

[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
for the per-variable selection frequencies, and
[`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)
for the same question asked of a correlated group.
[`fit_linear()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_linear.md),
[`fit_logistic()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_logistic.md)
and
[`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md)
are the supplied fitters.

## Examples

``` r
set.seed(1)
n  <- 300
x1 <- rnorm(n)
df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1,
                 x2 = rnorm(n), noise = rnorm(n))

# n_rep is RESAMPL=. It counts VALID models, so a replicate whose fit fails
# is redrawn and does not consume one -- the macro's &regrc check.
fit <- boot_select(df, y ~ x1 + x2 + noise, fit_linear,
                   n_rep = 50, seed = 42)
fit
#> <boot_selection>
#>   replicates: 50 valid of 50 attempts
#>   terms:      4
#> Use boot_summary() for per-variable selection frequencies.

# The replicate table itself, one row per model, NA where a term was not
# selected. This is what %bootreg writes to OUTEST=.
head(fit$coefficients, 3)
#>      (Intercept)       x1         x2     noise
#> [1,] -0.09140503 2.072650         NA        NA
#> [2,] -0.01488408 1.998002         NA        NA
#> [3,]  0.02101367 1.922324 0.09061786 0.0989286

boot_summary(fit)
#>      variable  n pct       mean         sd         min       max
#> 1 (Intercept) 50 100 -0.0161571 0.06298653 -0.15297676 0.1069145
#> 2          x1 50 100  2.0116268 0.08923849  1.88008851 2.2223719
#> 3          x2 15  30  0.1043906 0.01859431  0.08727983 0.1415486
#> 4       noise 13  26  0.1090360 0.01588121  0.08396326 0.1492700
```
