# Fitter contract
# ---------------
# A fitter takes (data, formula, select) and returns a NAMED NUMERIC VECTOR of
# the coefficients the model kept, or NULL if the fit failed.
#
# NULL rather than an error is deliberate: %bootreg checks &regrc after each
# proc and, when it is non-zero, resamples in place WITHOUT counting the
# attempt. Returning NULL is that contract -- boot_select() drops the replicate
# and draws another.
#
# A named vector rather than a model object is also deliberate: %bootreg writes
# outest=, one row per replicate, with a MISSING coefficient for any variable
# not selected. That missingness is exactly what %SUMBOOT counts, so the vector
# must carry only the kept terms and let the assembler supply NA elsewhere.

# Fit inside an environment that carries `data` and `formula`.
#
# This is not ceremony. stats::step() refits through add1()/drop1(), which
# re-evaluate the model's stored call in environment(formula(object)) -- the
# scope where the FORMULA was written, not the frame of whoever called step().
# A bootstrap replicate lives in a local variable, so that scope has no `data`;
# R then continues its search and finds utils::data, the function, and the fit
# dies with the memorable "'data' must be a data.frame, environment, or list".
#
# Rebinding the formula's environment to one holding this replicate's `data`
# puts the refit's lookups where they belong. Without it, every stepwise
# replicate fails and boot_select() -- whose default IS stepwise -- returns
# nothing at all.
.fit_in_env <- function(cl, formula, data) {
  env <- new.env(parent = environment(formula))
  environment(formula) <- env
  env$data <- data
  env$formula <- formula
  eval(cl, env)
}

# Stepwise both-directions, the closest R analogue to SAS SELECTION=STEPWISE.
# %bootreg's sle/sls are p-value thresholds; step() works on AIC, so the two
# cannot agree term for term. This is why fitting is NOT parity-tested: the
# selection mechanism is the model engine's, and the package's parity claim is
# scoped to the summariser. See the spec's parity table.
#
# No `scope` is passed. With scope missing, step() fixes the addable set to the
# STARTING model's terms and forces nothing to stay, so a term it drops can be
# re-admitted later. Started from the full model -- which is what we always do
# -- that is already both-directions selection. An explicit scope would add
# nothing and would have to special-case a Surv() response.
#
# `data` is declared and never referenced. It is still load-bearing, and it
# covers a DIFFERENT lookup path from .fit_in_env(): step() refits with
# eval.parent(update(object, ..., evaluate = FALSE)), which resolves the call's
# `data` in the frame of step()'s caller -- this function. .fit_in_env() fixes
# the add1()/drop1() model-frame path; this argument fixes the refit path.
# Both are required. Remove either and every stepwise replicate returns NULL.
.maybe_step <- function(fit, select, data) {
  if (!identical(select$method, "stepwise")) return(fit)
  steps <- if (isTRUE(select$max_steps > 0)) select$max_steps else 1000L
  stats::step(fit, direction = "both", trace = 0, steps = steps)
}

.coefs <- function(fit) {
  cf <- stats::coef(fit)
  cf <- cf[!is.na(cf)]
  if (length(cf) == 0L) return(NULL)
  cf
}

#' Fit a linear model for one bootstrap replicate
#'
#' @param data A data frame - one bootstrap replicate.
#' @param formula Model formula offering the candidate terms.
#' @param select List with `method` (`"stepwise"` or `"none"`), `sle`, `sls`,
#'   `max_steps`. `%bootreg` equivalents: `SELECT=`, `SLE=`, `SLS=`, `MAXSTEP=`.
#' @return Named numeric vector of kept coefficients, or `NULL` if the fit
#'   failed. `NULL` tells [boot_select()] to discard the replicate and draw
#'   another, reproducing `%bootreg`'s `&regrc` check.
#' @export
fit_linear <- function(data, formula, select) {
  tryCatch({
    fit <- .fit_in_env(quote(stats::lm(formula, data = data)), formula, data)
    .coefs(.maybe_step(fit, select, data))
  }, error = function(e) NULL, warning = function(w) NULL)
}

#' Fit a logistic model for one bootstrap replicate
#'
#' @inheritParams fit_linear
#' @return Named numeric vector of kept coefficients, or `NULL`.
#' @export
fit_logistic <- function(data, formula, select) {
  tryCatch({
    fit <- .fit_in_env(
      quote(stats::glm(formula, data = data, family = stats::binomial())),
      formula, data
    )
    if (!fit$converged) return(NULL)
    .coefs(.maybe_step(fit, select, data))
  }, error = function(e) NULL, warning = function(w) NULL)
}

#' Fit a Cox proportional-hazards model for one bootstrap replicate
#'
#' @inheritParams fit_linear
#' @return Named numeric vector of kept coefficients, or `NULL`. Cox models
#'   carry no intercept, so none appears in the result.
#' @export
fit_cox <- function(data, formula, select) {
  if (!requireNamespace("survival", quietly = TRUE))
    stop("`fit_cox()` needs the survival package.", call. = FALSE)
  tryCatch({
    fit <- .fit_in_env(quote(survival::coxph(formula, data = data)),
                       formula, data)
    .coefs(.maybe_step(fit, select, data))
  }, error = function(e) NULL, warning = function(w) NULL)
}
