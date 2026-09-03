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
# WARNINGS DO NOT DISCARD A REPLICATE. Only errors, and logistic
# non-convergence, produce NULL. glm routinely warns "fitted probabilities
# numerically 0 or 1" on a quasi-separated bootstrap replicate while still
# converging to usable coefficients; treating that as a failure threw away
# exactly the replicates where a predictor is strong, biasing the selection
# frequencies downward. &regrc is a return code, which SAS warnings do not
# set, so the macro keeps those models too.
#
# A named vector rather than a model object is also deliberate: %bootreg writes
# outest=, one row per replicate, with a MISSING coefficient for any variable
# not selected. That missingness is exactly what %SUMBOOT counts, so the vector
# must carry only the kept terms and let the assembler supply NA elsewhere.

# Fit inside an environment that carries `data` and `formula`.
#
# ORIGINAL JUSTIFICATION, NO LONGER TRUE: this wrapper existed because
# stats::step() refit through add1()/drop1(), which re-evaluate the model's
# stored call in environment(formula(object)) -- the scope where the FORMULA
# was written, not the frame of whoever called step(). Nothing in this
# package calls step() any more; the p-value stepwise driver, .pv_stepwise()
# in R/stepwise.R, refits with stats::update(fit, ..., data = data), passing
# `data` explicitly on every call rather than relying on a formula-environment
# lookup to find it.
#
# During the Task 3 review, ablating this rebinding entirely still left
# fit_linear(), fit_cox() and a full 20-replicate stepwise run all working.
# That is suggestive, not exhaustive, so the wrapper is kept rather than
# removed on that evidence alone -- whether it is still needed by anything is
# an open question worth a dedicated look, not a call to make in passing here.
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
# The single site where selection happens. `enter` and `remove` are pinned by
# the caller, never by boot_select()'s user: SLE= and SLS= then mean what they
# mean in the job being ported. See R/stepwise.R.
.maybe_step <- function(fit, select, data, enter, remove) {
  if (!identical(select$method, "stepwise")) return(fit)
  .pv_stepwise(fit, data, sle = select$sle, sls = select$sls,
               max_steps = select$max_steps, enter = enter, remove = remove)
}

# A zero-length result is NOT a failure. Cox carries no intercept, so a
# replicate where selection kept nothing has coef() of length zero. Returning
# NULL there made boot_select() treat a legitimate "nothing was selected"
# outcome as a failed fit and redraw it, which drops those replicates out of
# the pct denominator and inflates every variable's selection frequency.
# lm/glm never reach this: the intercept survives. NULL is reserved for a fit
# that genuinely produced no coefficient vector at all.
# coef() on an intercept-only coxph returns NULL rather than numeric(0), so
# both spellings of "this model kept nothing" must map to the same zero-length
# answer. .coefs() is only ever reached on a SUCCESSFUL fit -- failures are
# caught by the fitters' tryCatch -- so it never needs to signal failure.
.coefs <- function(fit) {
  cf <- stats::coef(fit)
  if (is.null(cf)) return(stats::setNames(numeric(0), character(0)))
  cf[!is.na(cf)]
}

#' Fit a linear model for one bootstrap replicate
#'
#' @param data A data frame - one bootstrap replicate.
#' @param formula Model formula offering the candidate terms.
#' @param select List with `method` (`"stepwise"` or `"none"`), `sle`, `sls`,
#'   `max_steps`. `%bootreg` equivalents: `SELECT=`, `SLE=`, `SLS=`, `MAXSTEP=`.
#' @return Named numeric vector of kept coefficients, or `NULL` if the fit
#'   failed. `NULL` tells [boot_select()] to discard the replicate and draw
#'   another, reproducing `%bootreg`'s `&regrc` check. A **warning** does not
#'   count as failure - the fit is kept, matching the macro, whose `&regrc` is
#'   a return code that warnings do not set. A zero-length result is likewise
#'   not a failure: it means selection kept no terms, which is a valid
#'   replicate.
#' @seealso [fit_logistic()] and [fit_cox()], the other two `PROC=` values
#'   `%bootreg` supports; [boot_select()], which calls a fitter once per
#'   replicate.
#' @examples
#' set.seed(1)
#' n  <- 200
#' x1 <- rnorm(n)
#' df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1, noise = rnorm(n))
#'
#' # `method = "stepwise"` is the macro's default; `"none"` is FIXED=1, which
#' # fits the model as written and bootstraps its coefficients instead.
#' fit_linear(df, y ~ x1 + noise,
#'            list(method = "stepwise", sle = 0.10, sls = 0.05, max_steps = 0))
#'
#' fit_linear(df, y ~ x1 + noise,
#'            list(method = "none", sle = 0.10, sls = 0.05, max_steps = 0))
#' @export
fit_linear <- function(data, formula, select) {
  tryCatch(
    suppressWarnings({
      fit <- .fit_in_env(quote(stats::lm(formula, data = data)), formula, data)
      .coefs(.maybe_step(fit, select, data, enter = "f", remove = "f"))
    }),
    error = function(e) NULL
  )
}

#' Fit a logistic model for one bootstrap replicate
#'
#' @inheritParams fit_linear
#' @return Named numeric vector of kept coefficients, or `NULL` if the fit
#'   errored or did not converge. Warnings - notably "fitted probabilities
#'   numerically 0 or 1" on a quasi-separated replicate - do not discard a
#'   converged fit.
#' @seealso [fit_linear()] and [fit_cox()]; [boot_select()].
#' @examples
#' set.seed(1)
#' n  <- 200
#' x1 <- rnorm(n)
#' df <- data.frame(y = as.integer(x1 + rnorm(n) > 0), x1 = x1,
#'                  noise = rnorm(n))
#'
#' fit_logistic(df, y ~ x1 + noise,
#'              list(method = "stepwise", sle = 0.10, sls = 0.05,
#'                   max_steps = 0))
#' @export
fit_logistic <- function(data, formula, select) {
  tryCatch(
    suppressWarnings({
      fit <- .fit_in_env(
        quote(stats::glm(formula, data = data, family = stats::binomial())),
        formula, data
      )
      if (!isTRUE(fit$converged)) NULL
      else .coefs(.maybe_step(fit, select, data, enter = "rao",
                              remove = "wald"))
    }),
    error = function(e) NULL
  )
}

#' Fit a Cox proportional-hazards model for one bootstrap replicate
#'
#' @details
#' **Divergence:** `PROC PHREG SELECTION=STEPWISE` enters a term on the score
#' chi-square. R has no score test for a Cox model - `anova.coxph()` accepts
#' `test = "Rao"` but silently ignores it and always returns the
#' likelihood-ratio test - so entry here is by likelihood ratio. The two agree
#' asymptotically and differ only for a term sitting on the entry threshold, so
#' a screen will usually select the same set and may occasionally differ on a
#' borderline candidate. Removal is Wald, matching the macro.
#'
#' @inheritParams fit_linear
#' @return Named numeric vector of kept coefficients, or `NULL` if the fit
#'   errored. Cox models carry no intercept, so none appears in the result -
#'   which means a replicate where selection kept nothing returns a
#'   **zero-length** vector, not `NULL`, and counts as a valid replicate.
#' @seealso [fit_linear()] and [fit_logistic()]; [boot_select()].
#' @examples
#' if (requireNamespace("survival", quietly = TRUE)) {
#'   set.seed(2)
#'   n  <- 200
#'   df <- data.frame(time = rexp(n), status = rbinom(n, 1, 0.7),
#'                    x1 = rnorm(n), noise = rnorm(n))
#'
#'   fit_cox(df, survival::Surv(time, status) ~ x1 + noise,
#'           list(method = "stepwise", sle = 0.10, sls = 0.05, max_steps = 0))
#' }
#' @export
fit_cox <- function(data, formula, select) {
  if (!requireNamespace("survival", quietly = TRUE))
    stop("`fit_cox()` needs the survival package.", call. = FALSE)
  tryCatch(
    suppressWarnings({
      fit <- .fit_in_env(quote(survival::coxph(formula, data = data)),
                         formula, data)
      .coefs(.maybe_step(fit, select, data, enter = "lr", remove = "wald"))
    }),
    error = function(e) NULL
  )
}
