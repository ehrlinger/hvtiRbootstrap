# Summarise bootstrap replicates into selection frequencies

The R port of `%SUMBOOT` (`bootstrap.summary.sas` in the CORR macro
library). For each candidate term: how often it was selected across
replicates, and the distribution of its coefficient when it was.

## Usage

``` r
boot_summary(x)
```

## Arguments

- x:

  A `boot_selection` from
  [`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md),
  or a numeric matrix with one row per replicate and one column per
  term.

## Value

A data frame with columns `variable`, `n`, `pct`, `mean`, `sd`, `min`,
`max`, sorted by descending `n`.

## Details

`n` counts replicates in which the term was selected, because
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
leaves an unselected term `NA`. `pct` is `100 * n / n_rep` - the
denominator is the replicate count, so `pct` reads as a selection
frequency.

This function is held to **exact parity** with `%SUMBOOT`: given the
same replicate table it must produce the same `n`, `pct`, `mean`, `sd`,
`min` and `max`. Resampling and model fitting are not parity-tested; see
the package's design spec.

## See also

[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md),
which produces the replicates;
[`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)
for the at-least-one count across a group of correlated terms.

## Examples

``` r
set.seed(1)
n  <- 300
x1 <- rnorm(n)
df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1,
                 x2 = rnorm(n), noise = rnorm(n))

fit <- boot_select(df, y ~ x1 + x2 + noise, fit_linear,
                   n_rep = 50, seed = 42)
boot_summary(fit)
#>      variable  n pct        mean          sd        min       max
#> 1 (Intercept) 50 100 -0.01935105 0.061297809 -0.1529768 0.1033970
#> 2          x1 50 100  2.01128028 0.090146372  1.8800885 2.2223719
#> 3       noise  3   6  0.12711552 0.019080164  0.1108547 0.1481200
#> 4          x2  3   6  0.13669590 0.007207413  0.1284142 0.1415486

# It also takes a bare replicate matrix, which is how the parity fixtures
# are checked against %SUMBOOT without needing any cohort data.
m <- matrix(c(1, 2, 3, 4, 2, NA, 4, NA), nrow = 4,
            dimnames = list(NULL, c("x1", "x2")))
boot_summary(m)
#>   variable n pct mean       sd min max
#> 1       x1 4 100  2.5 1.290994   1   4
#> 2       x2 2  50  3.0 1.414214   2   4
```
