# Fit a logistic model for one bootstrap replicate

Fit a logistic model for one bootstrap replicate

## Usage

``` r
fit_logistic(data, formula, select)
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

Named numeric vector of kept coefficients, or `NULL` if the fit errored
or did not converge. Warnings - notably "fitted probabilities
numerically 0 or 1" on a quasi-separated replicate - do not discard a
converged fit.

## See also

[`fit_linear()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_linear.md)
and
[`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md);
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md).

## Examples

``` r
set.seed(1)
n  <- 200
x1 <- rnorm(n)
df <- data.frame(y = as.integer(x1 + rnorm(n) > 0), x1 = x1,
                 noise = rnorm(n))

fit_logistic(df, y ~ x1 + noise,
             list(method = "stepwise", sle = 0.10, sls = 0.05,
                  max_steps = 0))
#> (Intercept)          x1 
#>  0.05094849  1.38932194 
```
