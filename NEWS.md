# hvtiRbootstrap (unreleased)

* The `NEWS.md` version test skips headings that carry no version, so merged
  work can sit under this heading without moving `DESCRIPTION`. The test read
  the first heading in the file and compared it against `DESCRIPTION`, which
  fails as soon as an unreleased heading is on top.
  It also reads only level-one headings, matching the family convention settled
  on 2026-09-01, and no longer accepts `#hvtiRbootstrap`, which CommonMark does
  not treat as a heading at all.
* **`boot_pool_chunks()` no longer reports a confidence interval it never
  computed.** `ci_lower` and `ci_upper` were quantiles taken over the
  replicates in which the term was *selected*, because `boot_bag()` writes
  `$boot$replicates` with `NA` dropped. For a term chosen in 30% of replicates
  that was an interval over 30% of them, and the weaker the term, the narrower
  its interval looked. They are now `sel_q025` and `sel_q975`, named for what
  they are: a sibling of `mean`, `sd`, `min` and `max`, which are conditional
  on selection in exactly the same way.
* **`boot_bag()` and `boot_pool_chunks()` now build `$boot$summary` through one
  constructor**, so the two cannot disagree. They had been building it
  separately, in two shapes with two different key columns -- `variable` from
  the bag, `parameter` from the pool -- so a renderer saw a different shape
  depending on whether the run happened to be chunked, and `boot_bag()`
  contradicted the key that `boot_validate()`'s own documented example uses.
  Both now key on `parameter`. `boot_summary()` is unchanged and keeps
  `variable`: it is the standalone `%SUMBOOT` port, not a bag.
* **`boot_validate()` checks `$boot$summary`'s columns**, not merely that the
  slot is filled. Nothing in the package reads that slot -- `boot_frequencies()`
  rebuilds from `$boot$replicates` -- so without this the two constructors
  could drift apart indefinitely without a test failing.
* **A bag saved by hvtiRbootstrap 0.9.2 is now refused by the whole reporting
  layer.** `boot_validate()`'s new column check requires the key `parameter`,
  and 0.9.2's `boot_bag()` wrote `$boot$summary` keyed `variable` -- so
  `boot_frequencies()`, `boot_dropped()`, `boot_health()`, `boot_provenance()`,
  `boot_seeds()` and `boot_concepts()`, which all gate on `boot_validate()`
  first, now refuse a bag that release wrote. The numbers in it were never
  wrong: nothing in the package reads `$boot$summary`, and `boot_frequencies()`
  rebuilds its table from `$boot$replicates` instead. Fix a saved bag `b` with

      names(b$boot$summary)[names(b$boot$summary) == "variable"] <- "parameter"

  or re-run `boot_bag()`.
* Quantiles on the selection branch use `stats::quantile(type = 4)`, which is
  SAS `PROC STDIZE`'s `PCTLDEF=1`, rather than R's `type = 7` default.

# hvtiRbootstrap 0.9.2

Finishes 0.9.1's sweep. That release made every *optional* bag field read by
exact name; this one does the same for the fields nothing was protecting, and
one of them was worse than 0.9.1's note claimed. It also gives a finished run
a way to say what it was, and a way to become a report.

## New features

* **A `boot_select()` run now records its own settings.** The returned object
  carries `$control`: `method`, `sle`, `sls`, `max_steps`, `fraction`, `seed`,
  `n_rows`, `n_terms`, `elapsed_mins` and the `package` version.

  `$call` cannot do that job, for a reason that is invisible until it bites.
  `match.call()` omits every argument left at its default, so a screen run the
  ordinary way -- taking `sle`, `sls` and `max_steps` as given -- has a `$call`
  naming none of the thresholds that produced it. A provenance table built from
  it prints blanks exactly where the screen's criteria belong, and the
  alternative is asking the caller to retype settings the run already knew.

  Recording them on the object means whatever assembles a bag can read the run
  rather than interview it.

* **`boot_bag()` assembles it.** It converts a `boot_select()` result into the
  bag `boot_validate()` accepts and every reporting function reads.

  The two ends of this package were built against different studies and had
  never met. `boot_select()` returns a *wide* object, one row per replicate and
  one column per term with `NA` where a term was not selected. The reporting
  layer reads a *long* one, because it was extracted from a hazard runner that
  writes long. Nothing converted between them, so the package's own screen
  function could not reach its own report, and every study would have
  hand-written the pivot plus nine provenance fields, differently each time.

  The pivot drops `NA` rather than recording it, and that is the whole design
  rather than a shortcut: `boot_frequencies()` counts a term's rows against
  `n_boot`, so a row written for an unselected term would be counted as a
  selection and every frequency in the report would rise.

  Four arguments, which are the facts a screen cannot know about itself: which
  terms are the base model, how many candidates were offered before any were
  dropped, the dataset manifest, and what was dropped. Everything else comes
  from `$control`, so a bag cannot claim an entry level the screen did not use.
  The result is validated before it is returned, so an invalid bag is never
  emitted to be refused three chunks into a render.

  **A Cox screen has no intercept.** `base_params = "(Intercept)"` copied from
  a logistic runner names nothing there, and is refused rather than silently
  excluding no terms and reporting the base model as a candidate.

* **`boot_provenance()` reads `engine`.** Its "Fitting engine" row looked for
  `th_sha` and then `th_version`, both written by TemporalHazard's hazard
  runner. A bag this package assembled has neither, so the row that exists to
  say *which codebase ran* printed `NA` on every `boot_select()` screen. That
  is the blank-where-provenance-belongs failure the table was built to prevent,
  occurring in the table itself. `boot_bag()` writes `engine`; the third branch
  reads it.

## Bug fixes

* **A bag missing `base_params` no longer validates.** `boot_validate()` read
  it with `$`, and `.chk_any()` asks only whether there is a value -- so a
  runner that wrote `base_params_original` and no `base_params` produced a bag
  that passed validation with the required field absent. 0.9.1's note said an
  absent required field was "reported as absent either way, only the message
  misdescribes what was found". That was true of `manifest` and `boot`. It was
  not true of this one.

  The consequence was silent rather than loud. `base_params` is what
  `boot_frequencies()` subtracts to get the candidate set and what
  `boot_health()` takes the free base parameter from, so the sibling
  substituted into both and every table downstream was computed against a base
  set the screen never had.

* **`boot_pool_chunks()`'s consistency gates read their fields by exact
  name.** This function calls no validator, so nothing stood between a chunk
  and a prefix match. Read by prefix, a gate compares *siblings* -- and when
  two chunks agreed on the sibling, the gate passed on evidence it never had.
  A pair of chunks recording `th_sha256` and no `th_sha` were pooled with
  their fitting engine reported as verified.

  That inverts what the gates are for. `boot_pool_chunks()` refuses to pool
  chunks that cannot be shown to be draws from the same screen, and the
  `no chunk records` branch exists precisely so that a check which did not
  happen is never mistaken for one that passed.

  Every chunk field is now exact: the six gated ones (`slentry`, `slstay`,
  `base_params`, `usable`, `max_steps`, `manifest`), the engine provenance
  pair (`th_sha`, `th_version`), and the ungated reads that pooled a wrong
  number rather than refusing (`seed`, `n_boot`, `elapsed_mins`, and the
  per-chunk success and failure counts).

* **`boot_validate()`'s `manifest` and `boot` messages now name what is
  actually wrong.** Both errored before, but described the sibling they had
  found rather than the field they had not.

# hvtiRbootstrap 0.9.1

Two defects in the reporting layer, and one mistake made twice: a field read
under an assumption about its shape that nothing enforced.

## Bug fixes

* **`boot_dropped()` no longer refuses a `dropped` field that is absent**
  (#21). `$` on a list falls back to prefix matching, so a runner that
  recorded only `dropped_collinear` resolved `bag$dropped` to that character
  vector, and `boot_dropped()` rejected it as the wrong type -- for a field
  the runner never wrote. The message named `bag$dropped` and sent its reader
  hunting for something that was not there.

  The shape it broke on is the one the documentation goes out of its way to
  promise: a screen that dropped nothing reports no rows rather than a fault.
  Any bag carrying a real `dropped` finds the exact match first and never saw
  this, which is why it took a constructed case to surface it, and why it is
  the worst distribution a defect can have -- invisible in every bag in hand,
  fatal in the case that was advertised.

  Every optional field is now read by exact name: `dropped`, `free_sd`,
  `n_chunks`, `seeds`, `th_sha` and `th_version`. The class is gone rather
  than the instance.

* **A per-phase `free_sd` is refused by `boot_validate()` rather than fatal
  in `boot_health()`** (#22). `boot_health()` branches on `free_sd` with a
  scalar `if`, so a length-2 value killed the call with a message naming
  neither the field nor the function -- and the validator had passed the bag
  happily on the way in.

  `free_sd` is scalar by contract. It is the standard deviation of the
  *first* free base parameter, and `boot_pool_chunks()`, its only writer,
  computes one number. So the validator now says so, alongside `n_boot` and
  `seed`, and fails with the field named. Absent stays valid: a single
  unchunked run went through no pooling and carries none.

# hvtiRbootstrap 0.9.0

The version moves from 0.1.x to 0.9.0 because the package has arrived at the
scope it was designed for. `boot_select()` and the fitters run the screen,
`boot_summary()` and `boot_clusters()` summarise it, `boot_pool_chunks()`
makes a run of days restartable, and this release adds the reporting layer
that turns a finished screen into tables. A study can now go from a candidate
pool to a finished report without leaving this package.

It is not 1.0.0, and the reason is specific: the **hazard fitter is still
deferred**. `fit_hazard()` does not exist, because the variants deserve
reading before an API is fixed, and a 1.0.0 that then grows a new fitter
family would be making a promise it has not earned. Chunk pooling has also
been exercised on one real shape rather than many.

Nothing in 0.1.2 was ever tagged or released, so its notes are carried here
rather than split across two version numbers.

## New features

* The **reporting layer**: `boot_validate()`, `boot_provenance()`,
  `boot_seeds()`, `boot_frequencies()`, `boot_dropped()`, `boot_concepts()`
  and `boot_health()`. Each replaces a chunk that every bootstrap report in
  `hvtiRtemplates` carried, so the logistic, linear and Cox reports can be
  thin templates rather than near-copies of the ~825-line hazard one. Four
  hand-synced copies of a report is a shape this family has watched drift
  before.

  The three that group their output — `boot_frequencies()`,
  `boot_concepts()` and, through them, everything built on their rows — take
  an optional **`phase`**: a function mapping a term to its phase. With
  `NULL` there is no phase dimension; a multiphase hazard screen passes its
  own term-splitting rule. That one argument is what lets a single code path
  serve four reports, and the alternative — the package serving three of them
  while the fourth keeps its own copy — reintroduces exactly the duplication
  the extraction removes.

  `boot_dropped()` and `boot_health()` take no `phase`, and that is not an
  omission. A candidate dropped before screening never became a model term,
  so `bag$dropped` carries its own `phase` column written by the runner that
  dropped it; and a health check is screen-wide. An argument that cannot do
  anything is worse than an absent one.

* **`boot_validate()` checks field *shapes*, not just presence**, and it is
  the piece of this that would have prevented the defect that motivated it.
  The chunk it replaces checked that eleven fields existed. It passed a real
  screen happily while `requested` was a length-2 vector the report could not
  render, and that shipped in three releases: a length-2 value against a
  length-13 column does not recycle, it errors, so the provenance table could
  not build on **any** multiphase screen.

  So `requested` and `usable` may be vectors and are checked as such, while
  `n_boot` and `seed` may not. `integer(0)` is refused on both sides of that
  line: it satisfies "is present" and then contributes no element rather than
  one, which collapses the table built from it. Every failure is reported at
  once, because an author fixing a runner wants the whole list.

* **A selection frequency now carries its error.** `boot_frequencies()`
  reports `mc_error` per variable rather than one figure for the table: the
  Monte-Carlo error is largest at 50% and shrinks towards either end, so a
  single quoted value overstates it at the top of the table and understates
  it in the middle — and the middle is where the retention decision is being
  made. `near_threshold` marks the variables whose retention would not
  survive a rerun with different seeds.

* **`boot_concepts()` answers the question a per-variable frequency cannot.**
  Competing forms of one concept split replicates between them, so each
  form's own frequency understates the concept; `pct_any` counts a replicate
  that took two forms **once**, for the same reason `boot_clusters()`'s
  `n_any` does. Two forms at 30% each are anywhere between 30% and 60% of
  replicates depending on how often the same replicate took both, and no
  marginal percentage records that — so it is computed from the replicates,
  and the computation *is* `boot_clusters()`, called rather than repeated.

* **`boot_health()` calls an empty screen a failure.** A screen that selected
  nothing is the signature of a formula that did not survive the
  per-replicate rewrite: the refit errors, the error is caught, the step
  accepts nothing, and the run halts with no warning and `n_failed = 0`. The
  summary then reads as a table of perfectly reliable variables. It returns
  its findings rather than stopping, so a report decides how to present them.

## Under the hood

* `n` and `pct` are `boot_summary()`'s, and the at-least-one count is
  `boot_clusters()`'. Neither is reimplemented in the new layer. Those two
  are the invariants this package is judged on — `NA` means a term was not
  selected, and "at least one" is not a sum — and each keeps exactly one
  implementation.

* Reporting reads a **wide** replicate matrix while a runner writes a
  **long** one, so the pivot moves here from the template. Its row count is
  `n_boot`, not the number of replicate ids present: a replicate that
  selected nothing outside the base model writes no rows at all, and
  counting ids would use a smaller denominator and inflate every frequency
  in the report. A replicate id outside `1..n_boot` is refused, because
  `boot_pool_chunks()` checks that only for the chunks it stacks and an
  out-of-range id lands on a neighbour's row rather than erroring.

# hvtiRbootstrap 0.1.1

## CI

* The **PDF-manual** (`check-manual.yaml`) and **pkgdown** gates arrive here,
  bringing this package level with the rest of the family. `AGENTS.md`'s
  workflow table is updated to match — it had a standing note to do exactly
  that when these files appeared.

  The site builds into `pkgdown-site/`, not the default `docs/`, which holds
  this project's plans and specs. `build_site_github_pages()` takes
  `dest_dir = "docs"` as an explicit default that **overrides** `destination:`
  in `_pkgdown.yml`, so the workflow passes it directly.


* Pooling for **chunked** bootstrap runs: `boot_pool_chunks()`,
  `boot_chunk_files()` and `boot_shortfall()`. Ported from a study's local `R/`,
  where they were unreachable by anything else.

  A screen that writes nothing until its last replicate is unrestartable — a
  run that dies at 90% yields nothing — and on one real study a single forward
  selection over 160 candidates per phase was still running at 22 minutes, with
  501 of them to do. Chunking makes such a run restartable; these fold the
  chunks back into one object of the same shape, so a report reads a pooled
  screen and a single-run screen the same way.

  Pooling is only legitimate when every chunk drew from the same data, ran the
  same screen, and no two shared a seed. **Each is checked rather than assumed,
  because none fails loudly on its own:** two chunks sharing a seed hold
  literally the same replicates, so pooling counts each twice and reports a
  Monte-Carlo error smaller than the run has; a dataset rewritten mid-run gives
  chunks that each look fine and describe different cohorts. Neither shows up
  as an error in a frequency table — both show up as a slightly different
  number.

  **Absence is checked before agreement**, and that order is the point. A field
  no chunk records formats identically in every chunk, passes unanimously, and
  hands back `NULL` as the agreed value. A gate that cannot tell "everyone
  agrees" from "nobody recorded it" is worse than no gate, because it reads as
  a check that happened. That is not hypothetical: `max_steps` was absent from
  every chunk in one fixture and the suite was green.

  Replicate ids are offset before stacking, since they run `1..n_boot` inside
  each chunk and would otherwise merge — a variable selected in two chunks
  counting once instead of twice, understating every frequency.

  `boot_shortfall()` answers whether the pool is the run that was *launched*.
  Pooling mid-run is reasonable; the hazard is that a partial pool produces a
  report wrong in no visible way, where every check passes and only the
  denominator is not the intended one. The expected totals must come from
  outside the chunks, because nothing in a chunk knows how many siblings it was
  launched alongside.

# hvtiRbootstrap 0.1.0

* Initial development version. Selection core only: `boot_select()`,
  `boot_summary()`, `boot_clusters()`, with logistic, linear and Cox fitters.
* `boot_select()` no longer reports a factor predictor as never selected. Its
  candidate columns are the dummy-coded coefficient names the fitters return,
  so a factor `sex` appears once as `sexM` rather than also as an all-`NA`
  `sex` column with `n = 0`.
* `boot_select()` restores the caller's RNG state on exit, so passing `seed`
  no longer changes later random draws in the calling script.
* The fitters keep a converged model that merely warned. Previously any
  warning - notably `"fitted probabilities numerically 0 or 1"` on a
  quasi-separated replicate - discarded the replicate, which biased selection
  frequencies against strong predictors. Errors and logistic non-convergence
  still reject.
* A model that selected no terms is now a valid replicate rather than a failed
  fit. This only affected Cox, which has no intercept to survive selection,
  and it had been inflating every variable's reported frequency.
* `boot_clusters()` rejects duplicated cluster names, and `boot_summary()`
  rejects a matrix without column names, instead of failing later with an
  unrelated message.
