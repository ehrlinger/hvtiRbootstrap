# Is a pooled screen the run that was launched?

Chunks land over hours, and pooling whatever is on disk mid-run is a
reasonable thing to want. The hazard is that **a partial pool produces a
report that is wrong in no visible way**: every health check passes,
every frequency is honestly computed, and only the denominator is not
the intended one.

## Usage

``` r
boot_shortfall(bag, expect_chunks, expect_boot)
```

## Arguments

- bag:

  A pooled object from
  [`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md),
  or a single run.

- expect_chunks:

  How many chunks were launched.

- expect_boot:

  How many replicates were wanted in total.

## Value

`NULL` when the pool is the run that was launched; otherwise a sentence
saying how it falls short, suitable for a callout.

## Details

The expected totals are the only thing that can catch it, and they must
come from **outside** the chunks — nothing in a chunk knows how many
siblings it was launched alongside.

Replicates are checked as well as chunks, because a chunk that ran short
is not a missing chunk and counting chunks alone would call that
complete. An **over**-count is reported too: it means either the
expectation is stale or a stray chunk from another run is being pooled,
and both are worth saying.

## See also

[`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
