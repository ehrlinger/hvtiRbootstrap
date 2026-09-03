# Package index

## 

Resample and fit — `%bootreg`

Start here. Fits a model on each of many bootstrap replicates and
records which terms each one kept. `PROC=` becomes the `fitter`
argument, and a term the model did not select is left missing — which is
what makes the counts downstream read as selection frequencies.

- [`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
  : Build a model by bootstrap resampling

## 

Summarise the replicates — `%SUMBOOT` and `%cluster`

Reach for these once you have replicates.
[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
gives the per-variable selection frequency and coefficient distribution;
[`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)
answers the question it cannot — how often *at least one* member of a
correlated group survived. Both are held to exact parity with the
macros.

- [`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
  : Summarise bootstrap replicates into selection frequencies
- [`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)
  : Aggregate selection frequencies over clusters of correlated
  variables

## 

Report over a screen

The model-agnostic reporting layer, extracted so that the logistic,
linear, Cox and hazard bootstrap reports are thin templates rather than
near-copies of one another.
[`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md)
checks that the screen a runner wrote has the shape a report reads; the
rest turn it into tables. The ones that group their rows take an
optional `phase`, so a multiphase hazard screen and a single-phase
logistic screen run down the same code path;
[`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md)
and
[`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
have nothing to group and take none.
[`boot_bag()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_bag.md)
is the way in from this package’s own screen:
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
returns a wide object and everything here reads a long one.

- [`boot_bag()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_bag.md)
  : A screen the reporting layer can read
- [`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md)
  : Check that a bootstrap bag has the shape a report reads
- [`boot_provenance()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_provenance.md)
  : Where a bootstrap screen came from
- [`boot_seeds()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_seeds.md)
  : Every seed a bootstrap screen used
- [`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md)
  : Selection frequencies, with the error they carry
- [`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md)
  : Candidates the screen never saw
- [`boot_concepts()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_concepts.md)
  : Selection frequencies grouped by concept
- [`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
  : Did the bootstrap screen actually run?

## 

Pool a chunked run

Needed only when a screen was run in chunks, which is how a run of days
is made restartable.
[`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
folds them into one object of the same shape, refusing to pool chunks
that did not draw from the same data or run the same screen;
[`boot_shortfall()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_shortfall.md)
says whether what you pooled is the run you launched, which nothing
inside a chunk can know.

- [`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
  : Pool chunked bootstrap runs into one screen
- [`boot_chunk_files()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_chunk_files.md)
  : Find the chunk files of a chunked bootstrap run
- [`boot_shortfall()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_shortfall.md)
  : Is a pooled screen the run that was launched?

## 

Fitters — one per `PROC=`

Passed to
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md),
one per model family. Use these when choosing the model type; write a
new one when adding a family, rather than a new pipeline. Each returns
the coefficients its model kept, or `NULL` when the fit failed and the
replicate should be redrawn.

- [`fit_linear()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_linear.md)
  : Fit a linear model for one bootstrap replicate
- [`fit_logistic()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_logistic.md)
  : Fit a logistic model for one bootstrap replicate
- [`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md)
  : Fit a Cox proportional-hazards model for one bootstrap replicate

## 

Band an estimate — `%BNMNR` and `%BNPREV`

The other branch. Everything above selects variables: refit on each
replicate, count which terms survived, and a term the model did not
choose is left missing. This does not select anything — it resamples to
put a band around an estimate, so the replicates are a distribution
rather than a vote and there is no missingness to read. `statistic` is
the `fitter` contract with the selection semantics removed. No argument
sets a coverage level, because no macro in the family takes one: both
the 95% and the 68% band come back, in columns named for their coverage.

- [`boot_predict_ci()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_predict_ci.md)
  : Band an estimate by bootstrap resampling

## Package overview

The shape of the port: three macros and three functions at the core,
with the pooling and reporting layers that grew around them.

- [`hvtiRbootstrap`](https://ehrlinger.github.io/hvtiRbootstrap/reference/hvtiRbootstrap-package.md)
  [`hvtiRbootstrap-package`](https://ehrlinger.github.io/hvtiRbootstrap/reference/hvtiRbootstrap-package.md)
  : hvtiRbootstrap: Bootstrap Model Building for the HVTI CORR Group
