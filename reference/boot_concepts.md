# Selection frequencies grouped by concept

A per-form selection frequency answers "how often was *this form*
selected". It cannot answer "how often was *this concept* selected", and
that is the number a paper quotes.

## Usage

``` r
boot_concepts(bag, concept_map, phase = NULL, threshold = NULL)
```

## Arguments

- bag:

  A bootstrap screen. Checked by
  [`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md).

- concept_map:

  A data frame with columns `variable` and `concept`, mapping each
  screened variable to the concept it is a form of. This is the
  **study's own vocabulary** and is received, never inferred: which
  names are forms of one thing is a fact about an institution's naming
  conventions, not about statistics. A variable the map does not name is
  treated as a concept of its own rather than dropped, so nothing leaves
  the concept view silently.

- phase:

  A function mapping a term to its phase, or `NULL`. As in
  [`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md):
  with `NULL` there is no phase dimension, and the `concept_map` is then
  keyed on whole terms rather than phase-stripped names.

- threshold:

  The retention cutoff, as a percentage, or `NULL`.

## Value

A data frame with one row per concept – per concept per phase when
`phase` is supplied – with columns `concept`, `n_forms`, `forms`,
`n_any`, `pct_any`, `best_form_pct`, `spread`, `n_retained` and
`retained`, plus `phase`. `n_retained` and `retained` are `NA` when no
`threshold` is given.

## Details

The gap runs both ways. Competing forms split replicates between them,
so a concept reads weaker than any single figure suggests; or two forms
both clear the cutoff and one finding is reported twice.

**`pct_any` is not a sum**, for the same reason
[`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)'s
`n_any` is not: a replicate that selected two forms of one concept
counts **once**. Two forms at 30% each are anywhere between 30% and 60%
of replicates depending entirely on how often the same replicate took
both, and no marginal percentage records that – so this is computed from
the replicate table, never from the summary. The computation is
[`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)'s,
called rather than repeated.

`spread` is `pct_any - best_form_pct`: how much the per-form view
understates the concept. A spread of zero means the concept has one form
and the two views agree.

`n_retained` is the crowding number. A phase that spent several of its
slots on forms of **one** concept is budget-limited by redundancy, and
that is invisible in a coefficient table; the concepts where
`n_retained > 1` are the crowded ones.

**Nothing here collapses
[`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md).**
Every form keeps its own row and its own frequency there, because two
forms of one concept may carry different information: on one real pool,
`in_zexp` **is** `1/zexp` and yet correlates with `zexp` at only -0.195,
because `zexp` spans a 4000-fold range. That study's published model
uses both, in the same phase, both significant. This table is an
additional view, not a replacement.

## See also

[`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md)
for the per-form view this groups, and
[`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)
for the same at-least-one count over a group named by declaration rather
than by name.

## Examples

``` r
bag <- list(
  n_boot = 4L, seed = 101, slentry = 0.07, slstay = 0.05,
  base_params = "base", requested = 4L, usable = 3L, n_rows = 500L,
  elapsed_mins = 120, manifest = list(sha256 = "abc123"),
  boot = list(
    replicates = data.frame(
      replicate = c(1L, 1L, 1L, 2L, 2L, 3L, 3L, 4L),
      parameter = c("base", "early.age", "early.ln_age",
                    "base", "early.age", "base", "early.ln_age", "base"),
      estimate  = c(1, 0.5, 0.4, 1.1, 0.6, 0.9, 0.3, 1.2)),
    summary = data.frame(parameter = "base", n = 4L, pct = 100),
    n_success = 4L, n_failed = 0L))

map <- data.frame(variable = c("age", "ln_age"), concept = c("Age", "Age"))

# Both forms sit at 50%, and replicate 1 took both -- so the concept is at
# 75%, not 100%.
boot_concepts(bag, map, phase = function(term) sub("[.].*$", "", term))
#>   phase concept n_forms       forms n_any pct_any best_form_pct spread
#> 1 early     Age       2 age, ln_age     3      75            50     25
#>   n_retained retained
#> 1         NA       NA
```
