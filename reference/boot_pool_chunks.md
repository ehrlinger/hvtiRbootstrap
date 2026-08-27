# Pool chunked bootstrap runs into one screen

Folds a list of chunk objects into a single object of the same shape, so
a report reads a pooled screen and a single-run screen the same way.

## Usage

``` r
boot_pool_chunks(chunks)
```

## Arguments

- chunks:

  A list of chunk objects, each carrying at least `seed`, `n_boot`,
  `slentry`, `slstay`, `base_params`, `usable`, `max_steps`,
  `elapsed_mins`, a `manifest` with an `md5` or `sha256`, an engine
  provenance field (`th_sha` or `th_version`), and a `boot` list with
  `replicates`, `n_success` and `n_failed`.

## Value

One object shaped like a single chunk, with `boot$replicates` stacked
and re-indexed, `boot$summary` recomputed, and `n_chunks`, `seeds` and a
joined `seed` string added.

## Details

Six things must agree for chunks to be draws from one screen, and each
is checked rather than assumed. **None of them fails loudly on its
own:**

- Two chunks sharing a **seed** contain literally the same replicates.
  Pooling them counts each twice, halves nothing, and reports a
  Monte-Carlo error smaller than the run actually has.

- A **dataset rewritten mid-run** gives chunks that each look fine and
  describe different cohorts.

- A different **step cap** changes the screen, not just its cost: under
  a tighter cap a variable that would have entered late never gets the
  chance.

Neither shows up as an error in a frequency table. Both show up as a
slightly different number.

**Absence is checked before agreement, and that order is the whole
point.** A field no chunk records formats identically in every chunk, so
it passes unanimously and the accessor hands back `NULL` as the agreed
value. A gate that cannot tell "everyone agrees" from "nobody recorded
it" is not a gate, and it is worse than having none, because it reads as
a check that happened. This was not hypothetical: `max_steps` was absent
from every chunk in one test fixture and the suite was green.

Replicate ids run `1..n_boot` **inside** each chunk, so they collide
across chunks and are offset before stacking. Without that, replicate 1
of chunk 2 merges into replicate 1 of chunk 1 and a variable selected in
both counts once instead of twice — understating every frequency, in a
table that looks entirely ordinary.

The pooled summary is **recomputed from the pooled replicates**, never
averaged across chunks: a percentage of a percentage is not a percentage
of the whole, and the chunks need not be the same size.

## See also

[`boot_chunk_files()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_chunk_files.md)
to find them,
[`boot_shortfall()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_shortfall.md)
to check the pool is the run that was launched, and
[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
for the per-variable frequencies.
