# Changelog

## hvtiRbootstrap 0.9.1

Two defects in the reporting layer, and one mistake made twice: a field
read under an assumption about its shape that nothing enforced.

### Bug fixes

- **[`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md)
  no longer refuses a `dropped` field that is absent**
  ([\#21](https://github.com/ehrlinger/hvtiRbootstrap/issues/21)). `$`
  on a list falls back to prefix matching, so a runner that recorded
  only `dropped_collinear` resolved `bag$dropped` to that character
  vector, and
  [`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md)
  rejected it as the wrong type – for a field the runner never wrote.
  The message named `bag$dropped` and sent its reader hunting for
  something that was not there.

  The shape it broke on is the one the documentation goes out of its way
  to promise: a screen that dropped nothing reports no rows rather than
  a fault. Any bag carrying a real `dropped` finds the exact match first
  and never saw this, which is why it took a constructed case to surface
  it, and why it is the worst distribution a defect can have – invisible
  in every bag in hand, fatal in the case that was advertised.

  Every optional field is now read by exact name: `dropped`, `free_sd`,
  `n_chunks`, `seeds`, `th_sha` and `th_version`. The class is gone
  rather than the instance.

- **A per-phase `free_sd` is refused by
  [`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md)
  rather than fatal in
  [`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)**
  ([\#22](https://github.com/ehrlinger/hvtiRbootstrap/issues/22)).
  [`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
  branches on `free_sd` with a scalar `if`, so a length-2 value killed
  the call with a message naming neither the field nor the function –
  and the validator had passed the bag happily on the way in.

  `free_sd` is scalar by contract. It is the standard deviation of the
  *first* free base parameter, and
  [`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md),
  its only writer, computes one number. So the validator now says so,
  alongside `n_boot` and `seed`, and fails with the field named. Absent
  stays valid: a single unchunked run went through no pooling and
  carries none.

## hvtiRbootstrap 0.9.0

The version moves from 0.1.x to 0.9.0 because the package has arrived at
the scope it was designed for.
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
and the fitters run the screen,
[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
and
[`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)
summarise it,
[`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
makes a run of days restartable, and this release adds the reporting
layer that turns a finished screen into tables. A study can now go from
a candidate pool to a finished report without leaving this package.

It is not 1.0.0, and the reason is specific: the **hazard fitter is
still deferred**. `fit_hazard()` does not exist, because the variants
deserve reading before an API is fixed, and a 1.0.0 that then grows a
new fitter family would be making a promise it has not earned. Chunk
pooling has also been exercised on one real shape rather than many.

Nothing in 0.1.2 was ever tagged or released, so its notes are carried
here rather than split across two version numbers.

### New features

- The **reporting layer**:
  [`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md),
  [`boot_provenance()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_provenance.md),
  [`boot_seeds()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_seeds.md),
  [`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md),
  [`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md),
  [`boot_concepts()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_concepts.md)
  and
  [`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md).
  Each replaces a chunk that every bootstrap report in `hvtiRtemplates`
  carried, so the logistic, linear and Cox reports can be thin templates
  rather than near-copies of the ~825-line hazard one. Four hand-synced
  copies of a report is a shape this family has watched drift before.

  The three that group their output —
  [`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md),
  [`boot_concepts()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_concepts.md)
  and, through them, everything built on their rows — take an optional
  **`phase`**: a function mapping a term to its phase. With `NULL` there
  is no phase dimension; a multiphase hazard screen passes its own
  term-splitting rule. That one argument is what lets a single code path
  serve four reports, and the alternative — the package serving three of
  them while the fourth keeps its own copy — reintroduces exactly the
  duplication the extraction removes.

  [`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md)
  and
  [`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
  take no `phase`, and that is not an omission. A candidate dropped
  before screening never became a model term, so `bag$dropped` carries
  its own `phase` column written by the runner that dropped it; and a
  health check is screen-wide. An argument that cannot do anything is
  worse than an absent one.

- **[`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md)
  checks field *shapes*, not just presence**, and it is the piece of
  this that would have prevented the defect that motivated it. The chunk
  it replaces checked that eleven fields existed. It passed a real
  screen happily while `requested` was a length-2 vector the report
  could not render, and that shipped in three releases: a length-2 value
  against a length-13 column does not recycle, it errors, so the
  provenance table could not build on **any** multiphase screen.

  So `requested` and `usable` may be vectors and are checked as such,
  while `n_boot` and `seed` may not. `integer(0)` is refused on both
  sides of that line: it satisfies “is present” and then contributes no
  element rather than one, which collapses the table built from it.
  Every failure is reported at once, because an author fixing a runner
  wants the whole list.

- **A selection frequency now carries its error.**
  [`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md)
  reports `mc_error` per variable rather than one figure for the table:
  the Monte-Carlo error is largest at 50% and shrinks towards either
  end, so a single quoted value overstates it at the top of the table
  and understates it in the middle — and the middle is where the
  retention decision is being made. `near_threshold` marks the variables
  whose retention would not survive a rerun with different seeds.

- **[`boot_concepts()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_concepts.md)
  answers the question a per-variable frequency cannot.** Competing
  forms of one concept split replicates between them, so each form’s own
  frequency understates the concept; `pct_any` counts a replicate that
  took two forms **once**, for the same reason
  [`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)’s
  `n_any` does. Two forms at 30% each are anywhere between 30% and 60%
  of replicates depending on how often the same replicate took both, and
  no marginal percentage records that — so it is computed from the
  replicates, and the computation *is*
  [`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md),
  called rather than repeated.

- **[`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
  calls an empty screen a failure.** A screen that selected nothing is
  the signature of a formula that did not survive the per-replicate
  rewrite: the refit errors, the error is caught, the step accepts
  nothing, and the run halts with no warning and `n_failed = 0`. The
  summary then reads as a table of perfectly reliable variables. It
  returns its findings rather than stopping, so a report decides how to
  present them.

### Under the hood

- `n` and `pct` are
  [`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)‘s,
  and the at-least-one count is
  [`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)’.
  Neither is reimplemented in the new layer. Those two are the
  invariants this package is judged on — `NA` means a term was not
  selected, and “at least one” is not a sum — and each keeps exactly one
  implementation.

- Reporting reads a **wide** replicate matrix while a runner writes a
  **long** one, so the pivot moves here from the template. Its row count
  is `n_boot`, not the number of replicate ids present: a replicate that
  selected nothing outside the base model writes no rows at all, and
  counting ids would use a smaller denominator and inflate every
  frequency in the report. A replicate id outside `1..n_boot` is
  refused, because
  [`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
  checks that only for the chunks it stacks and an out-of-range id lands
  on a neighbour’s row rather than erroring.

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
