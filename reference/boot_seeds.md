# Every seed a bootstrap screen used

One row per chunk, so that a rerun is reproducible and a duplicate is
visible.

## Usage

``` r
boot_seeds(bag)
```

## Arguments

- bag:

  A bootstrap screen. Checked by
  [`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md).

## Value

A data frame with columns `chunk` (integer) and `seed` (character).

## Details

Two chunks sharing a seed contain literally the **same** replicates:
pooling them counts each twice and reports a Monte-Carlo error smaller
than the run actually has.
[`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
refuses that outright, so a pooled screen cannot reach here with a
duplicate. This table is what lets you check a *single* run, and what
lets a reader reproduce either.

A single unchunked run never went through
[`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
and carries only the scalar `seed` its runner wrote, so that is used
when `seeds` is absent. Seeds are formatted without scientific notation:
a seed printed as `1.23e+08` cannot be typed back in.

## See also

[`boot_provenance()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_provenance.md),
which summarises the count.

## Examples

``` r
bag <- list(
  n_boot = 500L, seed = 4242, slentry = 0.07, slstay = 0.05,
  base_params = "base", requested = 230L, usable = 226L,
  n_rows = 4000L, elapsed_mins = 150, manifest = list(sha256 = "abc123"),
  boot = list(replicates = data.frame(replicate = 1L, parameter = "base",
                                      estimate = 1),
              summary = data.frame(parameter = "base", n = 1L, pct = 100),
              n_success = 500L, n_failed = 0L))
boot_seeds(bag)
#>   chunk seed
#> 1     1 4242
```
