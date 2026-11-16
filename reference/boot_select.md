# Build a model by bootstrap resampling

The R port of `%bootreg` (`bootstrap.models.sas` in the CORR macro
library). Fits `fitter` on each of `n_boot` bootstrap replicates and
records the coefficients each model kept.

## Usage

``` r
boot_select(
  data,
  formula,
  fitter,
  n_boot = 1000,
  fraction = 1,
  select = c("stepwise", "none"),
  sle = 0.1,
  sls = 0.05,
  max_steps = 0,
  max_attempts = 10 * n_boot,
  seed = NULL,
  n_rep
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

- n_boot:

  Number of **valid** models to generate (`%bootreg` `RESAMPL=`).
  Replicates whose fit fails are redrawn and do not count, matching the
  macro's `&regrc` check. That makes the result **conditional on
  estimability**: the replicates kept are those on which the model could
  be fitted. When more than 5% of draws fail the run warns, and
  [`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
  flags the rate.

- fraction:

  Fraction of `nrow(data)` to draw per replicate (`%bootreg`
  `FRACTION=`). **Divergence:** the macro documents this parameter but
  never applies it - it computes `ds_size * fraction`, prints it, and
  then always draws `ds_size` rows. This implementation applies it. Pass
  `fraction = 1` (the default) to match SAS behaviour exactly.

- select:

  `"stepwise"` or `"none"` (`%bootreg` `SELECT=`/`FIXED=`).

- sle, sls:

  Entry and retention p-value thresholds (`%bootreg` `SLE=`, `SLS=`).
  Each fitter pins its own entry and removal test to match its `PROC=` -
  see
  [`fit_linear()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_linear.md),
  [`fit_logistic()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_logistic.md)
  and
  [`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md) -
  so `sle` and `sls` are exactly what they mean in the job being ported.
  Model fitting is still not parity-tested - see the package's design
  spec - but these two arguments now select rather than only being
  recorded. **Divergence:** candidates are flat term labels, not a
  hierarchy, and
  [`fit_linear()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_linear.md)'s
  removal test respects marginality while
  [`fit_logistic()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_logistic.md)'s
  and
  [`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md)'s
  Wald removal test does not - so a screen can keep an interaction
  without either main effect on the latter two, which `PROC LOGISTIC`'s
  default `HIERARCHY=SINGLE` would not do. Not implemented; see D5 in
  the README's divergence register.

- max_steps:

  Maximum selection steps (`%bootreg` `MAXSTEP=`). `0` means no
  restriction, implemented as a budget scaled to the model - ten passes
  over the candidate terms, floored at 1000 - which no realistic model
  reaches. It bounds the p-value stepwise driver's forward/backward loop
  (`.pv_stepwise()` in `R/stepwise.R`) rather than leaving it genuinely
  unbounded.

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

- n_rep:

  Deprecated name for `n_boot`, renamed under the hvtiR API rubric. It
  still works for one release and warns once per session.

## Value

An object of class `boot_selection`. `$coefficients` is a matrix with
one row per valid replicate and one column per candidate term, `NA`
where the term was not selected. `$control` records the run's own
settings – `method`, `sle`, `sls`, `max_steps`, `fraction`, `seed`,
`n_rows`, `n_terms`, `elapsed_mins`, the `package` version, its commit
`sha` (`NA` when the installer recorded none), `rng_kind`, the `fitter`
(`"fit_linear"`, `"fit_logistic"`, `"fit_cox"`, or an md5 of a custom
fitter's source) and the deparsed `formula` – so that a bag builder
[`boot_bag()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_bag.md)
can take a provenance record from the run rather than from what a caller
retypes. `$call` cannot serve that purpose:
[`match.call()`](https://rdrr.io/r/base/match.call.html) omits every
argument left at its default. `$provenance` is the hvtiR family's shared
provenance record (`package`, `version`, `sha`, `method`, `seed`,
`rng_kind`, `time`), taken when the draw began, followed by this
package's `fitter` and `formula`. The replicate count stays in `$n_rep`.

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

# n_boot is RESAMPL=. It counts VALID models, so a replicate whose fit fails
# is redrawn and does not consume one -- the macro's &regrc check.
fit <- boot_select(df, y ~ x1 + x2 + noise, fit_linear,
                   n_boot = 50, seed = 42)
fit
#> <boot_selection>
#>   replicates: 50 valid of 50 attempts
#>   terms:      4
#> Use boot_summary() for per-variable selection frequencies.

# The replicate table itself, one row per model, NA where a term was not
# selected. This is what %bootreg writes to OUTEST=.
head(fit$coefficients, 3)
#>      (Intercept)       x1 x2 noise
#> [1,] -0.09140503 2.072650 NA    NA
#> [2,] -0.01488408 1.998002 NA    NA
#> [3,]  0.01221866 1.906206 NA    NA

boot_summary(fit)
#>      variable  n pct        mean          sd        min       max
#> 1 (Intercept) 50 100 -0.01935105 0.061297809 -0.1529768 0.1033970
#> 2          x1 50 100  2.01128028 0.090146372  1.8800885 2.2223719
#> 3       noise  3   6  0.12711552 0.019080164  0.1108547 0.1481200
#> 4          x2  3   6  0.13669590 0.007207413  0.1284142 0.1415486
```
