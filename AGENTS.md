# hvtiRbootstrap

Bootstrap variable selection: the R port of the CORR macro library's `%bootreg`,
`%SUMBOOT` and `%cluster`. The core is six exports — `boot_select()`,
`boot_summary()`, `boot_clusters()`, and the three fitters `fit_logistic()`,
`fit_linear()`, `fit_cox()` — with two layers around it that have no macro behind
them: **pooling** (`boot_pool_chunks()`, `boot_chunk_files()`, `boot_shortfall()`)
and **reporting** (`boot_validate()`, `boot_provenance()`, `boot_seeds()`,
`boot_frequencies()`, `boot_dropped()`, `boot_concepts()`, `boot_health()`).

**The parity scope is narrow and deliberate.** `boot_summary()` and `boot_clusters()`
are held to *exact* parity with `%SUMBOOT` and `%cluster`. Resampling and model fitting
are **not** parity-tested — they cannot be, since the two languages draw different
samples. Know which side of that line a change falls
on before claiming it matches SAS.

This file is the operational contract and applies in full. It is tool neutral, so Codex and
any other agent read the same rules. Claude Code affordances live in `CLAUDE.md`, which
imports this file.

## Definition of done

- `devtools::test()` passes. The runner is `tests/testthat.R`.
- `devtools::check()` is **0 errors, 0 warnings, 0 notes**. Verified 2026-09-01 at 0.9.0
  (22s with `--no-manual`; 31s under `--as-cran` with the manual built, from a clean
  `git archive` export, where the only NOTE is CRAN incoming feasibility).
- `devtools::document()` has been run and `man/` and `NAMESPACE` are committed with the
  source change.
- Any divergence from the macro is in the roxygen, marked **Divergence**, with the default
  chosen so that the default behaviour still matches SAS.

## The automated gates

Six workflows, now level with the rest of the family: the PDF-manual and pkgdown
gates arrived in 0.1.1.

| workflow | fails on |
|---|---|
| `R-CMD-check.yaml` | `R CMD check` across platforms |
| `check-manual.yaml` | `R CMD check --as-cran` **with the manual built** |
| `pkgdown.yaml` | the site build, including any exported topic missing from `_pkgdown.yml`'s reference index |
| `lint.yaml` | `lintr::lint_package()` |
| `house-style.yaml` | the composed house style |
| `test-coverage.yaml` | coverage upload |

Two things worth knowing about the pkgdown gate, both learned the hard way:

- **A new export fails the build until it is in the reference index.** That is the
  gate working, not an obstacle — an undocumented export is the thing it exists to
  catch. Add it to `_pkgdown.yml` in the same PR.
- **The site builds into `pkgdown-site/`, not `docs/`.** `docs/` holds this project's
  plans and specs, and pkgdown rightly refuses to build over a directory it did not
  create — with the deploy step's settings it would have published the plans as the
  package site. `build_site_github_pages()` takes `dest_dir = "docs"` as an explicit
  default that **overrides** `destination:` in `_pkgdown.yml`, so the workflow passes
  it directly.

## Rules for this repo

- **`NA` is the design. Do not fill it with zero.** A term the model did not select is `NA`
  in that replicate's row, and `boot_summary()` counts non-missing values down a column — so
  `n` *is* the number of replicates that chose the term. Replacing `NA` with `0` is the
  obvious-looking cleanup that silently destroys every selection frequency in the package.
- **A fitter returns a NAMED NUMERIC VECTOR of kept coefficients, or `NULL` on failure.**
  Not a model object: `%bootreg` writes `outest=` with one row per replicate and a *missing*
  coefficient for anything unselected, and that missingness is exactly what `%SUMBOOT`
  counts. The vector carries only the kept terms; the assembler supplies `NA` elsewhere.
- **`NULL` rather than an error is the contract.** `%bootreg` checks `&regrc` after each proc
  and, when non-zero, resamples in place **without counting the attempt**. `boot_select()`
  drops the replicate and draws another, so `n_rep` counts *valid* models.
- **WARNINGS DO NOT DISCARD A REPLICATE.** Only errors, and logistic non-convergence, return
  `NULL`. `glm` routinely warns *"fitted probabilities numerically 0 or 1"* on a
  quasi-separated bootstrap replicate while still converging to usable coefficients. Treating
  that warning as a failure **threw away exactly the replicates where a predictor is strong,
  biasing selection frequencies downward**. `&regrc` is a return code, and SAS warnings do
  not set it, so the macro keeps those models too. If you are tempted to add
  `tryCatch(warning = ...)` to a fitter, this is why not.
- **Adding a model family means writing a fitter, not another pipeline.** `fitter` is what
  `PROC=` was.
- **`boot_clusters()`'s `n_any` is not a sum.** A replicate that selected two members of a
  cluster counts **once** — the point is how often *at least one* member was chosen, because
  correlated terms split replicates between them and each one's individual frequency
  understates the cluster.
- **THIS PACKAGE DOES TWO JOBS, AND THEY ARE NOT THE SAME JOB.** *Selection*
  refits on each replicate and counts which terms survived - the replicates are
  a vote, and `NA` is how a vote is cast. *Intervals* resample to put a band
  around an estimate - the replicates are a distribution, nothing is selected,
  and there is no `NA` semantics at all. Everything shipped today is the
  selection branch. The interval branch (`%BNMNR`, `%BNPREV`, `bl_ord.*`) is
  built as `boot_predict_ci()` in `R/boot-intervals.R`. A CI-shaped output
  computed on the selection branch is the mistake this rule exists to stop:
  `boot_pool_chunks()` shipped `ci_lower`/`ci_upper` that were quantiles over
  only the replicates that selected the term, so the weaker the term the
  narrower its "interval" looked. They are now `sel_q025`/`sel_q975`.
  A fitter returns `NA` for a term the model did not choose; a `statistic`
  never does, because nothing is being chosen -- a missing estimate there is a
  broken replicate and the whole replicate is discarded. Do not carry the `NA`
  rule across the branch line in either direction.
- **Coverage lives in a column name, never in an argument.** No function in
  this package takes a confidence level. The macro family hardcodes
  `PCTLPTS=2.5 16 50 84 97.5` and returns both the 95% and the 68% band in
  named columns; a function that takes no level cannot mislabel one, which is
  the point. Quantiles are `stats::quantile(type = 4)`, SAS's `PCTLDEF=1`,
  never R's `type = 7` default.
- **The `fraction` divergence is deliberate and defaults to parity.** `%bootreg` documents
  `FRACTION=`, computes `ds_size * fraction`, prints it, and then always draws `ds_size`.
  This implementation actually applies it. The default `fraction = 1` reproduces SAS exactly,
  so a caller who wants the macro's behaviour gets it without knowing any of this.
- **Roxygen markdown is ENABLED** (`Roxygen: list(markdown = TRUE)`).
  ⚠️ `hvtiRutilities` and `hvtiRtemplates` have no such field and need Rd markup instead.
- **There is no `.lintr`**, so lintr's defaults apply, including the **80-character** limit.
  ⚠️ The family runs 80, 100, 120 and 135 in different repos. Read `.lintr` — or its absence.
- **`testthat` edition 3.** Test files are `test-*.R` with a hyphen.

## Gotchas

- The package is **0.x**. The **hazard fitter is deliberately deferred** — the variants
  were judged to deserve reading before an API is fixed, so `fit_hazard()` does not exist
  and should not be improvised. The quantile fitter
  ([#16](https://github.com/ehrlinger/hvtiRbootstrap/issues/16)),
  `boot_predict_ci()` and
  penalised selection are deferred the same way, each to its own spec. Those four
  deferrals are why this is 0.9.0 and not 1.0.0.
- **Chunking is done, not a gap.** ⚠️ This entry used to say the opposite, and an agent
  reading the old text could reimplement what already ships. `boot_pool_chunks()`,
  `boot_chunk_files()` and `boot_shortfall()` arrived in 0.1.1. The rule that entry
  anticipated is now a shipped property rather than a caution: the pooled summary
  **recomputes** `n` and `pct` from the pooled replicates rather than averaging across
  chunks, because a percentage of a percentage is not a percentage of the whole and the
  chunks need not be the same size.
- `DESCRIPTION` has no `Date:` field, so there is nothing to refresh on a version bump.
- There are no vignettes, so `R CMD check` is fast here. That is not evidence of coverage.

## Git and versioning

- **Never push to `main`.** Branch, then open a PR and let the maintainer merge.
- **`main` is protected by a GitHub ruleset, and nothing in this repo records that.** A clone
  shows no trace of it, so it is stated here. The ruleset is named `protect main`, is
  identical across all twelve repositories in the HVTI R package family, and enforces four
  rules on the default branch: no deletion, no force-push, pull-request-only, and an
  **automatic Copilot code review** on every PR. A rejected push comes from the server, not a
  local hook.
  ⚠️ It currently requires **zero approvals**. `require_code_owner_review` is set but inert
  because no repository in the family has a `CODEOWNERS` file, so a PR can merge unreviewed.
- Versions are **straight three digits** (`0.1.0`). Never a `.9000` suffix or a fourth digit.
- **Patch-digit bumps only.** Minor and major are the maintainer's decision.
- **Bump when you tag, not when you merge.** `DESCRIPTION` and the top `NEWS.md` heading
  must always match -- `tests/testthat/test-package.R` checks for exactly that -- but
  matching is the whole requirement, and it does not ask the number to be new. So while
  the top heading is a version that was never tagged, work lands as **bullets under it**
  rather than under a heading of its own.
  ⚠️ This bullet used to say to bump in the same commit as the change, which reads as once
  per PR. That mints versions nobody installs. As of 2026-09-01, 0.9.1 and 0.9.2 had both
  landed in a single afternoon while `v0.1.1` and `v0.9.0` were the only tags in the repo
  -- a snapshot, not a standing claim, and the state that prompted this rewording. The
  precedent is 0.9.0's own notes, which folded 0.1.2's entries in "rather than split
  across two version numbers"; this is that rule applied before the fact instead of after.
  The cost is real and worth paying: two branches adding bullets to the same heading
  conflict in `NEWS.md`. That is one small conflict per PR.

## Change discipline

1. **Think before coding.** Do not assume, ask. If the request is ambiguous or a name, path
   or signature is uncertain, surface the confusion rather than running with a guess.
2. **Simplicity first.** Write the minimum that solves the stated problem.
3. **Surgical changes.** Touch only what the task requires. Raise nearby problems separately.
4. **Goal-driven execution.** State what done looks like before starting, and use tests as the
   criterion. For anything touching selection frequencies, "done" includes checking that the
   `NA` semantics survived.

## Prose

Documentation prose follows the house voice. Every exported function's roxygen names the
macro it ports and the parameter it replaces — a reader arriving from SAS needs that mapping
more than they need an abstract description.
