#' @keywords internal
#'
#' @details
#' Three functions do the work:
#'
#' * [boot_select()] - resample, fit, and record which terms each model kept
#'   (`%bootreg`).
#' * [boot_summary()] - per-variable selection frequency and coefficient
#'   distribution (`%SUMBOOT`).
#' * [boot_clusters()] - how often at least one member of a correlated group was
#'   selected (`%cluster`).
#'
#' Fitters are pluggable: [fit_logistic()], [fit_linear()] and [fit_cox()] ship
#' with the package, and a new model family is a new fitter rather than a new
#' pipeline.
"_PACKAGE"
