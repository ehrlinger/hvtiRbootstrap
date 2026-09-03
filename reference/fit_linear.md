# Fit a linear model for one bootstrap replicate

Fit a linear model for one bootstrap replicate

## Usage

``` r
fit_linear(data, formula, select)
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

Named numeric vector of kept coefficients, or `NULL` if the fit failed.
`NULL` tells
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
to discard the replicate and draw another, reproducing `%bootreg`'s
`&regrc` check. A **warning** does not count as failure - the fit is
kept, matching the macro, whose `&regrc` is a return code that warnings
do not set. A zero-length result is likewise not a failure: it means
selection kept no terms, which is a valid replicate.

## Details

Under `select = "stepwise"`, entry and removal both test the partial F,
matching `PROC REG SELECTION=STEPWISE`.

## See also

[`fit_logistic()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_logistic.md)
and
[`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md),
the other two `PROC=` values `%bootreg` supports;
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md),
which calls a fitter once per replicate.

## Examples

``` r
set.seed(1)
n  <- 200
x1 <- rnorm(n)
df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1, noise = rnorm(n))

# `method = "stepwise"` is the macro's default; `"none"` is FIXED=1, which
# fits the model as written and bootstraps its coefficients instead.
fit_linear(df, y ~ x1 + noise,
           list(method = "stepwise", sle = 0.10, sls = 0.05, max_steps = 0))
#> (Intercept)          x1 
#>  0.04145787  1.97692216 

fit_linear(df, y ~ x1 + noise,
           list(method = "none", sle = 0.10, sls = 0.05, max_steps = 0))
#> (Intercept)          x1       noise 
#>  0.04040757  1.97877032 -0.02354057 
```
