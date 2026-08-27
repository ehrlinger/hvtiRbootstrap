# Changelog

## hvtiRbootstrap 0.1.1

### CI

- The **PDF-manual** (`check-manual.yaml`) and **pkgdown** gates arrive
  here, bringing this package level with the rest of the family.
  `AGENTS.md`’s workflow table is updated to match — it had a standing
  note to do exactly that when these files appeared.

  The site builds into `pkgdown-site/`, not the default `docs/`, which
  holds this project’s plans and specs. `build_site_github_pages()`
  takes `dest_dir = "docs"` as an explicit default that **overrides**
  `destination:` in `_pkgdown.yml`, so the workflow passes it directly.

- Pooling for **chunked** bootstrap runs:
  [`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md),
  [`boot_chunk_files()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_chunk_files.md)
  and
  [`boot_shortfall()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_shortfall.md).
  Ported from a study’s local `R/`, where they were unreachable by
  anything else.

  A screen that writes nothing until its last replicate is unrestartable
  — a run that dies at 90% yields nothing — and on one real study a
  single forward selection over 160 candidates per phase was still
  running at 22 minutes, with 501 of them to do. Chunking makes such a
  run restartable; these fold the chunks back into one object of the
  same shape, so a report reads a pooled screen and a single-run screen
  the same way.

  Pooling is only legitimate when every chunk drew from the same data,
  ran the same screen, and no two shared a seed. **Each is checked
  rather than assumed, because none fails loudly on its own:** two
  chunks sharing a seed hold literally the same replicates, so pooling
  counts each twice and reports a Monte-Carlo error smaller than the run
  has; a dataset rewritten mid-run gives chunks that each look fine and
  describe different cohorts. Neither shows up as an error in a
  frequency table — both show up as a slightly different number.

  **Absence is checked before agreement**, and that order is the point.
  A field no chunk records formats identically in every chunk, passes
  unanimously, and hands back `NULL` as the agreed value. A gate that
  cannot tell “everyone agrees” from “nobody recorded it” is worse than
  no gate, because it reads as a check that happened. That is not
  hypothetical: `max_steps` was absent from every chunk in one fixture
  and the suite was green.

  Replicate ids are offset before stacking, since they run `1..n_boot`
  inside each chunk and would otherwise merge — a variable selected in
  two chunks counting once instead of twice, understating every
  frequency.

  [`boot_shortfall()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_shortfall.md)
  answers whether the pool is the run that was *launched*. Pooling
  mid-run is reasonable; the hazard is that a partial pool produces a
  report wrong in no visible way, where every check passes and only the
  denominator is not the intended one. The expected totals must come
  from outside the chunks, because nothing in a chunk knows how many
  siblings it was launched alongside.

## hvtiRbootstrap 0.1.0

- Initial development version. Selection core only:
  [`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md),
  [`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md),
  [`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md),
  with logistic, linear and Cox fitters.
- [`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
  no longer reports a factor predictor as never selected. Its candidate
  columns are the dummy-coded coefficient names the fitters return, so a
  factor `sex` appears once as `sexM` rather than also as an all-`NA`
  `sex` column with `n = 0`.
- [`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
  restores the caller’s RNG state on exit, so passing `seed` no longer
  changes later random draws in the calling script.
- The fitters keep a converged model that merely warned. Previously any
  warning - notably `"fitted probabilities numerically 0 or 1"` on a
  quasi-separated replicate - discarded the replicate, which biased
  selection frequencies against strong predictors. Errors and logistic
  non-convergence still reject.
- A model that selected no terms is now a valid replicate rather than a
  failed fit. This only affected Cox, which has no intercept to survive
  selection, and it had been inflating every variable’s reported
  frequency.
- [`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)
  rejects duplicated cluster names, and
  [`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
  rejects a matrix without column names, instead of failing later with
  an unrelated message.
