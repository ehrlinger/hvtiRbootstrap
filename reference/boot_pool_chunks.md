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
  `replicates`, `n_success` and `n_failed`. An optional `resampled`
  (`"patients"` or `"rows"`) defaults to `"rows"`.

## Value

One object shaped like a single chunk, with `boot$replicates` stacked
and re-indexed, `boot$summary` recomputed, `resampled` set to the agreed
value, and `n_chunks`, `seeds` and a joined `seed` string added.

## Details

Nine things must agree for chunks to be draws from one screen, and each
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

- Chunks that **resampled differently** – `resampled = "patients"`
  against `"rows"` on start/stop data – drew from different
  distributions. A chunk that records no `resampled` predates patient
  resampling and is read as `"rows"`, which is what every earlier runner
  did; the pooled object carries the agreed value.

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

## Examples

``` r
# Two chunks as the hazard runner writes them: same screen, different seeds.
chunk <- function(seed) list(
  seed = seed, n_boot = 2L, slentry = 0.1, slstay = 0.05,
  base_params = "early.log_mu", usable = c(early = 10L), max_steps = 50L,
  elapsed_mins = 1, manifest = list(sha256 = "example"),
  th_version = "1.2.16",
  boot = list(n_success = 2L, n_failed = 0L, replicates = data.frame(
    replicate = c(1L, 1L, 2L), parameter = c("early.log_mu", "early.age",
    "early.log_mu"), estimate = c(0.1, 0.02, 0.2)))
)
pooled <- boot_pool_chunks(list(chunk(1), chunk(2)))
pooled$n_boot
#> [1] 4
pooled$boot$summary
#>      parameter n pct mean         sd  min  max sel_q025 sel_q975
#> 1 early.log_mu 4 100 0.15 0.05773503 0.10 0.20     0.10     0.20
#> 2    early.age 2  50 0.02 0.00000000 0.02 0.02     0.02     0.02

# The same seed twice is the same replicates twice, so it is refused.
try(boot_pool_chunks(list(chunk(1), chunk(1))))
#> Error : boot_pool_chunks(): two chunks share the seed 1. Same seed means the SAME replicates, so pooling would count them twice and understate the Monte-Carlo error.
```
