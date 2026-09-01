# Did the bootstrap screen actually run?

Four facts about a screen, two of which are checks that catch a run
which produced a perfectly ordinary-looking table of numbers that mean
nothing.

## Usage

``` r
boot_health(bag)
```

## Arguments

- bag:

  A bootstrap screen. Checked by
  [`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md).

## Value

A data frame with one row per check and columns `check`, `value`, `ok`
and `note`. `ok` is `FALSE` for a failed check, `TRUE` for a passed one,
and `NA` for a row that is a fact rather than a check. `note` says what
a failure means and is `NA` otherwise.

## Details

**A screen that selected nothing is a failure, not a finding.** It is
the signature of a formula that did not survive the per-replicate
rewrite: the refit errors, the error is caught, the step reports nothing
accepted, and the screen halts having selected nothing – with no warning
and `n_failed = 0`. The summary then reads as a table of perfectly
reliable variables. Absence from a frequency table cannot say this; a
row that says `ok = FALSE` can.

**A free base parameter must vary across resamples.** A bootstrap built
on a vector interface returns the original fit every replicate, with
`n_success = 500`, `n_failed = 0` and no warning at all. The standard
deviation of the first free base parameter is the only tell, and a value
of exactly zero is that failure. It is `NA`, never `0`, when there is
nothing to take a standard deviation of: zero is the *claim* that the
parameter did not vary, and one replicate cannot support it.

`free_sd` is recomputed when the screen does not carry it. Only
[`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
writes that field, so a single unchunked run has none – and an unchunked
run is the shape most likely to have been built the way this check
exists to catch. Skipping it there would turn the check off in exactly
the case that needs it.

This function **returns** its findings rather than stopping. A report
decides how to present them: a callout, a red cell, or a
[`stop()`](https://rdrr.io/r/base/stop.html) of its own.

## See also

[`boot_provenance()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_provenance.md)
for where the screen came from, and
[`boot_shortfall()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_shortfall.md)
for whether the pool is the run that was launched – a different
question, and one nothing inside a chunk can answer.

## Examples

``` r
bag <- list(
  n_boot = 4L, seed = 101, slentry = 0.07, slstay = 0.05,
  base_params = "base", requested = 4L, usable = 3L, n_rows = 500L,
  elapsed_mins = 120, manifest = list(sha256 = "abc123"),
  boot = list(
    replicates = data.frame(
      replicate = c(1L, 1L, 2L, 3L, 4L),
      parameter = c("base", "early.age", "base", "base", "base"),
      estimate  = c(1, 0.5, 1.1, 0.9, 1.2)),
    summary = data.frame(parameter = "base", n = 4L, pct = 100),
    n_success = 4L, n_failed = 0L))
boot_health(bag)
#>                                 check     value   ok note
#> 1              Replicates that fitted         4 TRUE <NA>
#> 2              Replicates that failed         0   NA <NA>
#> 3   Distinct candidates ever selected         1 TRUE <NA>
#> 4 SD of the first free base parameter 0.1290994 TRUE <NA>

# A screen that selected nothing outside the base model.
bag$boot$replicates <- bag$boot$replicates[-2, ]
boot_health(bag)
#>                                 check     value    ok
#> 1              Replicates that fitted         4  TRUE
#> 2              Replicates that failed         0    NA
#> 3   Distinct candidates ever selected         0 FALSE
#> 4 SD of the first free base parameter 0.1290994  TRUE
#>                                                                                                                                                                                                                                                                                                                                                                                             note
#> 1                                                                                                                                                                                                                                                                                                                                                                                           <NA>
#> 2                                                                                                                                                                                                                                                                                                                                                                                           <NA>
#> 3 The screen selected NOTHING: no parameter outside the base model appears in any replicate. That is a failed screen, not a null result. It is what a model formula held in a variable looks like from here -- the per-replicate refit errors, the error is caught, and the step simply accepts nothing, so n_failed is 0. Write the formula literally at the call site in the runner and rerun.
#> 4                                                                                                                                                                                                                                                                                                                                                                                           <NA>
```
