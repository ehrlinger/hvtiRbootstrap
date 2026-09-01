# hvtiRbootstrap: Bootstrap Model Building for the HVTI CORR Group

Builds models by bootstrap resampling, in the manner of the Cleveland
Clinic CORR group's SAS macro library: fit a model on each of many
bootstrap replicates, record which variables survive selection, and
report how often each appeared. Ports the 'bootreg', 'SUMBOOT' and
'cluster' macros.

## Details

**Three macros, three functions.** That is the core, and to run a screen
it is still all there is to learn:

- [`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md) -
  resample, fit, and record which terms each model kept (`%bootreg`).

- [`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md) -
  per-variable selection frequency and coefficient distribution
  (`%SUMBOOT`).

- [`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md) -
  how often at least one member of a correlated group was selected
  (`%cluster`).

Fitters are pluggable, standing in for `%bootreg`'s `PROC=`:
[`fit_logistic()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_logistic.md),
[`fit_linear()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_linear.md)
and
[`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md)
ship with the package, and a new model family arrives as a new fitter
rather than a new pipeline.

Two layers have grown around that core. Neither has a macro behind it,
because a SAS batch job never needed one.

**Pooling**, for a screen too long to run in one go. A bootstrap that
writes nothing until its last replicate is unrestartable, and a real
screen can be days of compute.
[`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
folds chunk files into one object of the same shape, refusing chunks
that did not draw from the same data or run the same screen;
[`boot_chunk_files()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_chunk_files.md)
finds them, and
[`boot_shortfall()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_shortfall.md)
says whether what you pooled is the run you launched.

**Reporting**, for turning a finished screen into tables.
[`boot_validate()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_validate.md)
checks that the screen a runner wrote has the shape a report reads;
[`boot_provenance()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_provenance.md)
and
[`boot_seeds()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_seeds.md)
say where it came from;
[`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md)
and
[`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md)
give the per-term view, with the Monte-Carlo error each frequency
carries;
[`boot_concepts()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_concepts.md)
groups competing forms of one thing; and
[`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
says whether the screen ran at all, which is not the same question as
whether it finished.

The hinge of the whole design is that a term the model did not select is
`NA` in that replicate's row, so counting non-missing values down a
column gives the selection frequency directly. That is how the macros
work, and the port keeps it.

[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
and
[`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)
are held to **exact parity** with the macros. Resampling is stochastic
and model fitting belongs to `glm`, `lm` and `coxph`, so neither is
parity-tested; where R and SAS diverge on purpose, the README's
divergence section and the function's own help say so.

## See also

Useful links:

- <https://github.com/ehrlinger/hvtiRbootstrap>

- <https://ehrlinger.github.io/hvtiRbootstrap/>

- Report bugs at <https://github.com/ehrlinger/hvtiRbootstrap/issues>

## Author

**Maintainer**: John Ehrlinger <ehrlinj@ccf.org>

Authors:

- John Ehrlinger <ehrlinj@ccf.org>
