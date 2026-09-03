# Aggregate selection frequencies over clusters of correlated variables

When several candidate terms measure the same thing - weight and body
surface area, say - each one's individual selection frequency
understates the cluster's importance, because replicates split between
them. This reports how often **at least one** member of a cluster was
selected. The R port of `%cluster` (`bootstrap.clusters.sas` in the CORR
macro library).

## Usage

``` r
boot_clusters(x, clusters)
```

## Arguments

- x:

  A `boot_selection` from
  [`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md),
  or a numeric matrix with one row per replicate and one column per
  term.

- clusters:

  Named list mapping a cluster name to its member terms.

## Value

A data frame with columns `cluster`, `n_any`, `pct_any`, `members`,
sorted by descending `n_any`.

## Details

`n_any` is not the sum of the members' individual counts: a replicate
that selected two members counts once.

The macro also tabulates its `ncluster` counter - the full distribution
of *how many* members appeared together in a replicate. That is
deliberately not reproduced: the per-variable frequencies are already
[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)'s
job, and "at least one" is the number neither function can derive from
the other.

## See also

[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
for the per-variable frequencies, and
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md),
which produces the replicates.

## Examples

``` r
set.seed(1)
n  <- 300
x1 <- rnorm(n)
df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1,
                 x2 = rnorm(n), noise = rnorm(n))

fit <- boot_select(df, y ~ x1 + x2 + noise, fit_linear,
                   n_rep = 50, seed = 42)

# x1 and x2 stand in for a correlated pair -- weight and body surface area,
# say. n_any is not the sum of their individual counts: a replicate that
# selected both counts once.
boot_clusters(fit, list(size = c("x1", "x2"), noise = "noise"))
#>   cluster n_any pct_any members
#> 1    size    50     100  x1, x2
#> 2   noise     3       6   noise
```
