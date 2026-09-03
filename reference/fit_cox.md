# Fit a Cox proportional-hazards model for one bootstrap replicate

Fit a Cox proportional-hazards model for one bootstrap replicate

## Usage

``` r
fit_cox(data, formula, select)
```

## Arguments

- data:

  A data frame - one bootstrap replicate.

- formula:

  Model formula offering the candidate terms.

- select:

  List with `method` (`"stepwise"` or `"none"`), `sle`, `sls`,
  `max_steps`. `%bootreg` equivalents: `SELECT=`, `SLE=`, `SLS=`,
  `MAXSTEP=`.

## Value

Named numeric vector of kept coefficients, or `NULL` if the fit errored.
Cox models carry no intercept, so none appears in the result - which
means a replicate where selection kept nothing returns a **zero-length**
vector, not `NULL`, and counts as a valid replicate.

## Details

**Divergence:** `PROC PHREG SELECTION=STEPWISE` enters a term on the
score chi-square. R has no score test for a Cox model - `anova.coxph()`
accepts `test = "Rao"` but silently ignores it and always returns the
likelihood-ratio test - so entry here is by likelihood ratio. The two
agree asymptotically and differ only for a term sitting on the entry
threshold, so a screen will usually select the same set and may
occasionally differ on a borderline candidate. Removal is Wald, matching
the macro.

## See also

[`fit_linear()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_linear.md)
and
[`fit_logistic()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_logistic.md);
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md).

## Examples

``` r
if (requireNamespace("survival", quietly = TRUE)) {
  set.seed(2)
  n  <- 200
  df <- data.frame(time = rexp(n), status = rbinom(n, 1, 0.7),
                   x1 = rnorm(n), noise = rnorm(n))

  fit_cox(df, survival::Surv(time, status) ~ x1 + noise,
          list(method = "stepwise", sle = 0.10, sls = 0.05, max_steps = 0))
}
#>      noise 
#> -0.1851346 
```
