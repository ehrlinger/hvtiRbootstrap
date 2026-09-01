# Candidates the screen never saw

The candidates a runner dropped before screening, with the reason each
was dropped.

## Usage

``` r
boot_dropped(bag)
```

## Arguments

- bag:

  A bootstrap screen. Checked by
  [`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md).

## Value

A data frame of the dropped candidates, with no rows when nothing was
dropped.

## Details

A candidate the screen never saw **cannot appear at any frequency**, so
its absence from
[`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md)
is indistinguishable from never having been selected. That is the whole
reason this table exists: without it, a constant column and a genuinely
unselected variable read the same way.

Whatever columns the runner wrote are kept. Rows are ordered by `phase`
and then `reason` when those columns are present, so that a reader meets
whole classes of dropped candidate together rather than scattered down a
table that runs to dozens of rows on a real pool.

Unlike
[`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md)
and
[`boot_concepts()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_concepts.md)
this takes **no `phase` argument.** `bag$dropped` carries its own
`phase` column, written by the runner that did the dropping, so there is
nothing for a term-splitting rule to do; a candidate dropped before
screening never became a model term.

`dropped` is not a required field. A runner that drops nothing may not
write it at all, and that is reported as no rows rather than as a fault.

## See also

[`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md)
for the candidates that were screened.

## Examples

``` r
bag <- list(
  n_boot = 4L, seed = 101, slentry = 0.07, slstay = 0.05,
  base_params = "base", requested = 4L, usable = 3L, n_rows = 500L,
  elapsed_mins = 120, manifest = list(sha256 = "abc123"),
  dropped = data.frame(variable = c("zexp", "agee"),
                       phase = c("late", "early"),
                       reason = c("constant", "all missing")),
  boot = list(
    replicates = data.frame(replicate = 1L, parameter = "base",
                            estimate = 1),
    summary = data.frame(parameter = "base", n = 1L, pct = 25),
    n_success = 4L, n_failed = 0L))
boot_dropped(bag)
#>   variable phase      reason
#> 1     agee early all missing
#> 2     zexp  late    constant
```
