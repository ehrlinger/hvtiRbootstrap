# Where a bootstrap screen came from

The facts a reader needs to judge, reproduce or reject a screen: how
many replicates, under which entry and stay criteria, over how many
candidates and rows, at what cost, against which dataset and which build
of the fitting engine.

## Usage

``` r
boot_provenance(bag)
```

## Arguments

- bag:

  A bootstrap screen: the object
  [`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
  returns, or a single unchunked run of the same shape. Checked by
  [`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md).

## Value

A data frame with columns `item` and `value`, both character, one row
per fact. **The row count does not depend on the shape of any field**

- a per-phase `requested` yields the same rows as a scalar one.

## Details

`requested` and `usable` are **per phase** on a multiphase screen, and
rendering them is the reason this function exists rather than a bare
[`data.frame()`](https://rdrr.io/r/base/data.frame.html) call in each
report. They are collapsed to one labelled string per row –
`"early 230, late 230"` – and never summed: the candidate pool is
*offered* to each phase, so 230 and 230 is one pool seen twice rather
than 460 candidates.

Two facts travel with a tag that says what kind of evidence they are:

- The **dataset checksum** is `"<algo>:<digest>"`. An md5 and a sha256
  of the same file are different strings, and of different files may not
  be, so a bare digest recorded without its algorithm is not evidence of
  anything.

- The **fitting engine** is `"sha:<commit>"` in preference to
  `"version:<string>"`. One real package version existed as two
  codebases, one with a selection criterion and one without, and the
  selection criterion is precisely the thing that decides what a screen
  selects.

Elapsed time is reported as **summed CPU hours**, not wall clock:
[`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
sums `elapsed_mins` across chunks, so on a chunked run this is total
compute and chunks run in parallel finish in a fraction of it.

Seeds are summarised here and listed by
[`boot_seeds()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_seeds.md).
At 25 chunks the joined seed string is a single 270-character cell.

## See also

[`boot_seeds()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_seeds.md)
for the seeds themselves,
[`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
for whether the screen ran, and
[`boot_shortfall()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_shortfall.md)
for whether the pool is the run that was launched.

## Examples

``` r
bag <- list(
  n_boot = 500L, n_chunks = 2L, seed = "101, 202", seeds = c(101, 202),
  slentry = 0.07, slstay = 0.05, base_params = "base",
  requested = c(early = 230L, late = 230L),
  usable = c(early = 226L, late = 226L),
  n_rows = 4000L, elapsed_mins = 150, th_sha = "deadbeef",
  manifest = list(sha256 = "abc123"),
  boot = list(replicates = data.frame(replicate = 1L, parameter = "base",
                                      estimate = 1),
              summary = data.frame(parameter = "base", n = 1L, pct = 100),
              n_success = 500L, n_failed = 0L))
boot_provenance(bag)
#>                      item                     value
#> 1       Replicates pooled                       500
#> 2           Chunks pooled                         2
#> 3   Entry level (slentry)                      0.07
#> 4     Stay level (slstay)                      0.05
#> 5      Candidates offered       early 230, late 230
#> 6       Candidates usable       early 226, late 226
#> 7           Rows screened                      4000
#> 8  Replicates that fitted                       500
#> 9  Replicates that failed                         0
#> 10     CPU hours (summed)                       2.5
#> 11         Fitting engine              sha:deadbeef
#> 12       Dataset checksum             sha256:abc123
#> 13                  Seeds 2 distinct (listed below)
boot_seeds(bag)
#>   chunk seed
#> 1     1  101
#> 2     2  202
```
