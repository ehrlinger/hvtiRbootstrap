#' @keywords internal
#'
#' @details
#' Three macros, three functions:
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
