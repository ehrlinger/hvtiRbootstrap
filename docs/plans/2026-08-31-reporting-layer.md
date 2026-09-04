# Bootstrap Reporting Layer Implementation Plan

> **STATUS: SHIPPED in 0.9.0. This plan is a historical record, not work to do.** Every
> step below is ticked because the work landed; the checkboxes are kept so the plan
> reads as it was executed. Do not reimplement any of it -- read `NEWS.md` under
> `# hvtiRbootstrap 0.9.0` for what actually shipped, and the source for how.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the model-agnostic reporting computation out of
`hvtiRtemplates`' `bh` template and into this package, so `bl`, `br` and `bc`
can be thin templates instead of ~825-line near-copies.

**Architecture:** Six new exports returning data frames, plus a bag validator
that checks field **shapes** rather than presence. Every function takes an
optional `phase` argument so one code path serves the multiphase hazard screen
and the single-phase logistic / linear / Cox screens.

**Tech Stack:** R, testthat edition 3, roxygen2 with markdown, pkgdown.

**Why this exists:** `hvtiRtemplates`'
`dev/specs/2026-08-31-batch-2a-bootstrap-family-design.md` (merged, PR #60).
Read §3, §4 and §6 of it before starting — this plan implements them and
decides nothing they left open.

## Global Constraints

- **Never push to `main`.** Branch, open a PR **against `main`**, let the
  maintainer merge. A stacked PR does not trigger the Copilot review.
- **Lines are 80 characters.** There is no `.lintr`, so lintr's defaults apply.
  ⚠️ The family runs 80, 100, 120 and 135 in different repos — this one is 80,
  unlike `hvtiRtemplates` at 135. Do not carry a habit across.
- **Roxygen here IS markdown** (`Roxygen: list(markdown = TRUE)` in
  `DESCRIPTION`). Backticks and `**bold**` work. ⚠️ `hvtiRtemplates` is the
  opposite and needs `\code{}`; do not carry that habit across either.
- **Every new export must be added to `_pkgdown.yml`'s reference index in the
  same PR**, or `pkgdown.yaml` fails the build. That gate is working as
  intended — an undocumented export is what it exists to catch.
- **`DESCRIPTION` has no `Date:` field.** There is nothing to refresh on a bump.
- **Straight three-digit version, patch digit only.** Bump `DESCRIPTION` and add
  the matching `NEWS.md` entry in the same commit. **One tag for the whole
  plan**, not one per task: packages are moving under the `hvtiR` meta-package,
  where each tag is a member re-resolution and another `update()` downstream.
- **`testthat` edition 3.** Test files are `test-*.R`, with a hyphen.
- ⚠️ **`NA` in a replicate row is meaningful.** `boot_select()` leaves an
  unselected term `NA`, and `boot_summary()` counts non-missing values down a
  column — so `n` *is* the number of replicates that chose the term. **Replacing
  `NA` with `0` silently destroys every selection frequency in the package.**
  Nothing in this plan may do it.
- **Resampling and model fitting are not parity-tested** and cannot be; the two
  languages draw different samples. Everything in this plan is on the
  *reporting* side of that line, which **is** held to parity.

## What "the template does it today" means

Every task below lifts logic from
`hvtiRtemplates/inst/templates/analyses/04.05-bh.qmd` at v1.0.17, naming exact
chunk line ranges. **Read the chunk before writing the function**: its comments
record why each step is there, and several exist because the alternative failed
quietly. Carry the reasoning into the roxygen; do not re-derive it.

⚠️ **Do not copy the `kable()` calls, the prose, or any `EDIT:` marker.** Those
stay in the template. This package owns computation and validation only, so a
study author can still change what the report *says* without editing this repo.

## File Structure

| file | responsibility |
|---|---|
| `R/boot-validate.R` | `boot_validate()` — bag contract, checked by shape |
| `R/boot-provenance.R` | `boot_provenance()`, `boot_seeds()` |
| `R/boot-frequencies.R` | `boot_frequencies()`, `boot_dropped()` |
| `R/boot-concepts.R` | `boot_concepts()` |
| `R/boot-health.R` | `boot_health()` |
| `tests/testthat/test-boot-*.R` | one file per source file above |
| `_pkgdown.yml` | a reference section for the new group |
| `DESCRIPTION`, `NEWS.md` | one patch bump at the end |

**Not in scope, and each for a stated reason:**

- `boot_completeness()` — **`boot_shortfall(bag, expect_chunks, expect_boot)`
  already does this.** Do not add a second function for it.
- Collinearity — `bh`'s `collinear` chunk (lines 731-758) calls `read_built()`,
  which needs a study tree. It stays in the template.
- Anything that renders. No `kable()`, no `ggplot2`, no figure.

---

### Task 1: `boot_validate()` — check shapes, not just presence

**Files:**
- Create: `R/boot-validate.R`
- Create: `tests/testthat/test-boot-validate.R`

**Interfaces:**
- Consumes: a pooled bag from `boot_pool_chunks()`.
- Produces: `boot_validate(bag)` — returns `invisible(TRUE)` on a good bag,
  `stop()`s otherwise. Tasks 2-5 all call it first.

**This is the most important task in the plan.** The template's existing
`contract` chunk (lines 265-296) checks that eleven fields are **present**. It
passed a real bag happily while `requested` was a length-2 vector the template
could not handle, and the resulting defect shipped in three releases. Four
defects in this template family share that shape — a field read out of an
artifact produced by another package — and this function is the one piece of
this extraction that would have prevented the one that motivated it.

- [x] **Step 1: Write the failing tests**

```r
test_that("boot_validate accepts a well-formed bag", {
  bag <- fake_bag()
  expect_true(boot_validate(bag))
})

test_that("boot_validate names every missing field at once", {
  bag <- fake_bag()
  bag$seed <- NULL
  bag$n_rows <- NULL
  err <- expect_error(boot_validate(bag))
  expect_match(conditionMessage(err), "seed")
  expect_match(conditionMessage(err), "n_rows")
})

test_that("boot_validate rejects a scalar field that is not scalar", {
  # The defect this function exists to catch. `n_boot` is one number; a
  # length-2 value means the pool was written per phase into a field that
  # is not per phase, and every count downstream is then ambiguous.
  bag <- fake_bag()
  bag$n_boot <- c(500L, 500L)
  expect_error(boot_validate(bag), "n_boot")
})

test_that("boot_validate accepts a per-phase field being per phase", {
  # `requested` and `usable` ARE per phase on a multiphase screen. This is
  # the case that must NOT error -- it is valid, and the template's job is
  # to render it, not to reject it.
  bag <- fake_bag()
  bag$requested <- c(early = 230L, late = 230L)
  bag$usable <- c(early = 226L, late = 226L)
  expect_true(boot_validate(bag))
})

test_that("boot_validate rejects a zero-length field", {
  # character(0) satisfies "is present" and destroys any table built from
  # it, because it contributes no element rather than one.
  bag <- fake_bag()
  bag$n_rows <- integer(0)
  expect_error(boot_validate(bag), "n_rows")
})

test_that("boot_validate checks the nested boot fields", {
  bag <- fake_bag()
  bag$boot$n_success <- NULL
  expect_error(boot_validate(bag), "boot\\$n_success")
})
```

Add `fake_bag()` to `tests/testthat/helper-fixtures.R`, returning a list with
every field the contract names: `n_boot`, `seed`, `slentry`, `slstay`,
`base_params`, `usable`, `requested`, `n_rows`, `elapsed_mins`, `manifest`, and
`boot` carrying `replicates`, `summary`, `n_success`, `n_failed`. Give
`requested` and `usable` scalar values by default so the per-phase test is
visibly the variation.

- [x] **Step 2: Run them and watch them fail**

```
Rscript -e 'devtools::test(filter = "boot-validate")'
```
Expected: every test errors with "could not find function `boot_validate`".

- [x] **Step 3: Implement**

The specification, in full:

- **Required scalar fields** — `n_boot`, `seed`, `slentry`, `slstay`, `n_rows`,
  `elapsed_mins`. Each must be present, length exactly 1, and not `NA`.
- **Required fields that may be per phase** — `requested`, `usable`. Each must
  be present, length **at least** 1, and numeric. A length > 1 value is valid;
  named is preferred and not required.
- **Required fields of any shape** — `base_params`, `manifest`.
- **Required nested** — `boot$replicates`, `boot$summary`, `boot$n_success`,
  `boot$n_failed`.
- **Report every failure at once**, not the first. An author fixing a runner
  wants the whole list; one-at-a-time turns a single fix into five renders.
- The message must name the field, what was expected and what was found —
  `"n_boot: expected a single value, found length 2"` — because the error a
  study author sees is the only documentation they will read.

- [x] **Step 4: Run the tests**

```
Rscript -e 'devtools::test(filter = "boot-validate")'
```
Expected: `FAIL 0`, all tests passing.

- [x] **Step 5: Commit**

```bash
git add R/boot-validate.R tests/testthat/test-boot-validate.R tests/testthat/helper-fixtures.R
git commit -m "feat: boot_validate() checks bag field shapes, not just presence"
```

---

### Task 2: `boot_provenance()` and `boot_seeds()`

**Files:**
- Create: `R/boot-provenance.R`, `tests/testthat/test-boot-provenance.R`

**Interfaces:**
- Consumes: `boot_validate()` from Task 1.
- Produces: `boot_provenance(bag)` → a data frame with columns `item` and
  `value`, one row per fact. `boot_seeds(bag)` → a data frame of the per-chunk
  seeds.

Lift from `bh` chunks `provenance` (lines 299-377) and `seeds` (lines 380-396).

⚠️ **The per-phase handling is the whole point of this function's existence.**
`bag$requested` and `bag$usable` are vectors on a multiphase screen. The
template's `.per_phase()` helper renders `c(early = 230, late = 230)` as
`"early 230, late 230"` — **not summed**, because the pool is *offered* to each
phase, so 230 and 230 is one pool seen twice rather than 460 candidates. Move
that helper here, keeping its three cases: length 0 → `NA_character_` (a
zero-length value must still yield exactly one row, or the data frame collapses),
length 1 → the value, length > 1 → labelled if named, comma-joined if not.

**Tests must cover all four shapes** — zero-length, scalar, named vector,
unnamed vector — and assert the returned data frame has the same number of rows
in every case. That last assertion is the one that would have caught the
original defect.

- [x] **Step 1: Write the failing tests** (the four shapes above, plus that
  `boot_provenance()` calls `boot_validate()` and propagates its error)
- [x] **Step 2: Run them and watch them fail**
- [x] **Step 3: Implement, lifting from the named chunks**
- [x] **Step 4: Run the tests**
- [x] **Step 5: Commit** — `feat: boot_provenance() and boot_seeds()`

---

### Task 3: `boot_frequencies()` and `boot_dropped()`

**Files:**
- Create: `R/boot-frequencies.R`, `tests/testthat/test-boot-frequencies.R`

**Interfaces:**
- Produces: `boot_frequencies(bag, phase = NULL, threshold = NULL)` → columns
  `variable`, `n`, `pct`, `mc_error`, `near_threshold`, plus `phase` when
  `phase` is supplied. `boot_dropped(bag, phase = NULL)` → the dropped
  candidates with their reasons.

Lift from `bh` chunks `criteria` (502-512), `frequencies` (515-546), `retained`
(549-556), `dropped-summary` (406-415) and `dropped-detail` (418-422).

**`phase` is the argument that makes one code path serve four templates.**
When `NULL` there is no phase dimension and no `phase` column. When supplied it
is a **function** that maps a term to its phase; `bh` passes
`function(term) sub("[.].*$", "", term)`, which turns `early.age` into `early`.
Do not hardcode that rule here — a logistic screen has no phases and a future
model family may split terms differently.

⚠️ `boot_summary()` already computes `n` and `pct`. **Call it; do not
reimplement it.** What this function adds is `mc_error`, `near_threshold` and
the optional phase grouping. Reimplementing the frequency count would create a
second implementation of the one thing this package is parity-tested on.

- [x] **Step 1: Write the failing tests** — including one asserting
  `boot_frequencies(bag)` and `boot_summary(bag$boot$replicates)` agree on `n`
  and `pct` for every term, which pins the no-second-implementation rule
- [x] **Step 2: Run them and watch them fail**
- [x] **Step 3: Implement**
- [x] **Step 4: Run the tests**
- [x] **Step 5: Commit** — `feat: boot_frequencies() and boot_dropped()`

---

### Task 4: `boot_concepts()`

**Files:**
- Create: `R/boot-concepts.R`, `tests/testthat/test-boot-concepts.R`

**Interfaces:**
- Produces: `boot_concepts(bag, concept_map, phase = NULL)` → per-concept
  selection frequencies and the union count.

Lift from `bh` chunks `concept-map` (575-588), `concept-frequencies` (591-603),
`concept-union` (612-651) and `concept-counts` (660-673).

⚠️ **The union is not a sum**, for the same reason `boot_clusters()`'s `n_any`
is not: a replicate selecting two forms of one concept counts **once**, because
correlated forms split replicates between them and each form's individual
frequency understates the concept. That rule is already documented in
`AGENTS.md` for clusters — this function must obey it too, and its tests must
include a replicate selecting two forms of one concept.

⚠️ `concept_map` is the study's own vocabulary and stays an `EDIT:` marker in
the template. This function **receives** it; it must not infer one.

- [x] **Step 1: Write the failing tests**, including the two-forms-one-replicate
  case above
- [x] **Step 2: Run them and watch them fail**
- [x] **Step 3: Implement**
- [x] **Step 4: Run the tests**
- [x] **Step 5: Commit** — `feat: boot_concepts()`

---

### Task 5: `boot_health()`

**Files:**
- Create: `R/boot-health.R`, `tests/testthat/test-boot-health.R`

**Interfaces:**
- Produces: `boot_health(bag)` → a data frame of checks with a pass/fail column.

Lift from `bh` chunk `health` (433-485). Its defining behaviour is that **a
screen which selected nothing is a failure, not an empty table** — that is what
the chunk was written for, and the test suite must assert it.

`boot_health()` **returns** its findings rather than stopping, because the
template decides how to present them. But an empty selection must be
unmistakable in the returned frame, not merely absent from it.

- [x] **Step 1: Write the failing tests**, including a bag where no replicate
  selected any term
- [x] **Step 2: Run them and watch them fail**
- [x] **Step 3: Implement**
- [x] **Step 4: Run the tests**
- [x] **Step 5: Commit** — `feat: boot_health()`

---

### Task 6: Document, index, and release

**Files:**
- Modify: `_pkgdown.yml`, `DESCRIPTION`, `NEWS.md`

- [x] **Step 1: Add a reference section to `_pkgdown.yml`**

The existing index is organised by the SAS macro each group ports, with a
`desc:` explaining when to reach for it. Follow that shape — a new section
after the summarise group, listing `boot_validate`, `boot_provenance`,
`boot_seeds`, `boot_frequencies`, `boot_dropped`, `boot_concepts`,
`boot_health`.

⚠️ **All seven must appear, or `pkgdown.yaml` fails the build.** That is the
gate working. Do not add a `destination:` — the workflow passes
`dest_dir = "pkgdown-site"` explicitly, and `docs/` holds these plans.

- [x] **Step 2: Run `document()` and check the site builds**

```
Rscript -e 'devtools::document()'
Rscript -e 'pkgdown::build_site(dest_dir = "pkgdown-site")'
```
Expected: no "topic missing from index" error.

- [x] **Step 3: Bump the version and write NEWS**

Patch digit only. `DESCRIPTION` has **no `Date:`** — do not add one. One entry
covering the whole plan, naming what each function replaces in the template and
why the extraction happened.

- [x] **Step 4: The full gate**

```
Rscript -e 'lintr::lint_package()'
Rscript -e 'devtools::test()'
Rscript -e 'devtools::check()'
```
Expected: no lints (**80 characters**); `FAIL 0`; `0 errors | 0 warnings |
0 notes`.

- [x] **Step 5: Commit, push, open the PR against `main`**

Not stacked. Then confirm scope with
`gh api repos/ehrlinger/hvtiRbootstrap/compare/main...<branch> --jq '{ahead:.ahead_by, files:[.files[].filename]}'`
and check that only the files this plan names appear.

---

## What happens next, in the other repo

This plan ends when this package releases. `hvtiRtemplates` then:

1. ✅ **The baseline already exists**, captured 2026-08-31 after the v1.0.17
   fix: `~/Documents/templates/bh-baseline-20260831/`, sha256
   `da4e39d5…4f6a749`. Its README records the bag, the three edits made to the
   scaffolded job, and why each was needed. Re-render with the same three edits
   and the same bag, then `diff`.

   ⚠️ It lives **outside git**: the chunks are bootstrap replicates from a real
   study and the render carries its variable names and selection frequencies,
   while `hvtiRtemplates` is public and forbids study identifiers.

   ⚠️ It is also a **local copy of the bag on purpose** — the first attempt to
   capture this failed because `/Volumes/qhsstudies` had unmounted mid-session.
2. Rewrites `04.05-bh.qmd` onto these functions — **ordinal and filename
   unchanged**, body only — and verifies it result-identical against that
   baseline.
3. Ships `bl`, `br` and `bc` as thin templates.

`bq` waits on [#16](https://github.com/ehrlinger/hvtiRbootstrap/issues/16) in
this repo. `bn` is a different job and needs its own design.

## Self-review notes

**Spec coverage.** Design §4 boundary → the "What the template does today"
section and the not-in-scope list. §4.1 phase-awareness → Task 3's `phase`
argument, reused in Tasks 2 and 4. §6 shape-checking → Task 1.

**Deliberately not implemented:** `boot_completeness()` (duplicates
`boot_shortfall()`), collinearity (needs `read_built()`), and all presentation.

**The known sharp edge.** Tasks 2-5 lift logic that has been run exactly once
— the `bh` render on 2026-08-31 that found the per-phase defect. The chunks are
not proven beyond that single bag, so each task's tests are the first real
coverage this logic will have. Write them against the shapes named in each
task, not against whatever the one bag happened to contain.
