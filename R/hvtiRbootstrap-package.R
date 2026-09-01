#' @keywords internal
#'
#' @details
#' **Three macros, three functions.** That is the core, and to run a screen it
#' is still all there is to learn:
#'
#' * [boot_select()] - resample, fit, and record which terms each model kept
#'   (`%bootreg`).
#' * [boot_summary()] - per-variable selection frequency and coefficient
#'   distribution (`%SUMBOOT`).
#' * [boot_clusters()] - how often at least one member of a correlated group was
#'   selected (`%cluster`).
#'
#' Fitters are pluggable, standing in for `%bootreg`'s `PROC=`:
#' [fit_logistic()], [fit_linear()] and [fit_cox()] ship with the package, and a
#' new model family arrives as a new fitter rather than a new pipeline.
#'
#' Two layers have grown around that core. Neither has a macro behind it,
#' because a SAS batch job never needed one.
#'
#' **Pooling**, for a screen too long to run in one go. A bootstrap that writes
#' nothing until its last replicate is unrestartable, and a real screen can be
#' days of compute. [boot_pool_chunks()] folds chunk files into one object of
#' the same shape, refusing chunks that did not draw from the same data or run
#' the same screen; [boot_chunk_files()] finds them, and [boot_shortfall()]
#' says whether what you pooled is the run you launched.
#'
#' **Reporting**, for turning a finished screen into tables.
#' [boot_validate()] checks that the screen a runner wrote has the shape a
#' report reads; [boot_provenance()] and [boot_seeds()] say where it came from;
#' [boot_frequencies()] and [boot_dropped()] give the per-term view, with the
#' Monte-Carlo error each frequency carries; [boot_concepts()] groups competing
#' forms of one thing; and [boot_health()] says whether the screen ran at all,
#' which is not the same question as whether it finished.
#'
#' The hinge of the whole design is that a term the model did not select is
#' `NA` in that replicate's row, so counting non-missing values down a column
#' gives the selection frequency directly. That is how the macros work, and the
#' port keeps it.
#'
#' `boot_summary()` and `boot_clusters()` are held to **exact parity** with the
#' macros. Resampling is stochastic and model fitting belongs to `glm`, `lm` and
#' `coxph`, so neither is parity-tested; where R and SAS diverge on purpose, the
#' README's divergence section and the function's own help say so.
"_PACKAGE"
