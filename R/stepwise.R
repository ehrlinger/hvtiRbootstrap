# A p-value stepwise, in the shape PROC's SELECTION=STEPWISE has.
#
# WHY NOT stats::step(). Two reasons, and they are #31 and #32. step() refits
# the whole model for every candidate in both directions at every step, which
# costs roughly the 3.7th power of the pool -- about 450 hours for a real
# 172-candidate screen at n_rep = 500. And it selects on AIC, whose penalty of
# 2 per parameter retains a term at p < 0.157, so `sle` and `sls` were recorded
# on the bag, printed by boot_provenance(), and never applied.
#
# The criteria are pinned per family by the fitter, not chosen by the caller:
# `sle` and `sls` then mean exactly what SLE= and SLS= mean in the job being
# ported. See dev/specs/2026-09-03-pvalue-stepwise-design.md.

# The p-value for ADDING one term. NA when the test cannot be computed -- a
# candidate that will not refit is one the screen skips, not a failed replicate.
.pv_enter_p <- function(fit, term, data, criterion) {
  # ERRORS ONLY -- a quasi-separated candidate converges to usable
  # coefficients while glm warns "fitted probabilities numerically 0 or 1".
  # Catching that warning would return NA and refuse entry to exactly the
  # candidates where a predictor is strong, the same downward bias the
  # fitter contract in R/fitters.R exists to avoid. The fitters already run
  # the whole fit inside suppressWarnings(), so nothing here needs to catch
  # one.
  bigger <- tryCatch(
    stats::update(fit, stats::as.formula(paste(". ~ . +", term)),
                  data = data),
    error = function(e) NULL
  )
  if (is.null(bigger)) return(NA_real_)
  tab <- tryCatch(
    switch(criterion,
           f   = stats::anova(fit, bigger, test = "F"),
           rao = stats::anova(fit, bigger, test = "Rao"),
           lr  = stats::anova(fit, bigger)),
    error = function(e) NULL
  )
  if (is.null(tab)) return(NA_real_)
  col <- grep("^(Pr|P)\\(", names(tab), value = TRUE)
  if (!length(col)) return(NA_real_)
  as.numeric(tab[[col[[1L]]]][2L])
}

# Wald chi-square for one term's whole coefficient block.
#
# PER TERM, NOT PER COEFFICIENT. A three-level factor has two coefficients and
# PROC tests the term on two degrees of freedom. Reading one coefficient's
# Pr(>|z|) is right for a numeric term and wrong for every factor, which is the
# worst kind of wrong: it looks correct in the simple case.
.pv_wald_term <- function(fit, j) {
  b <- stats::coef(fit)[j]
  v <- tryCatch(stats::vcov(fit)[j, j, drop = FALSE],
                error = function(e) NULL)
  if (is.null(v) || anyNA(b) || anyNA(v)) return(NA_real_)
  w <- tryCatch(drop(t(b) %*% solve(v) %*% b), error = function(e) NA_real_)
  if (!is.finite(w)) return(NA_real_)
  stats::pchisq(w, df = length(b), lower.tail = FALSE)
}

# One p-value per term currently in the model, named by term label.
.pv_remove_p <- function(fit, criterion) {
  labs <- attr(stats::terms(fit), "term.labels")
  if (!length(labs)) return(stats::setNames(numeric(0), character(0)))
  if (identical(criterion, "f")) {
    tab <- tryCatch(stats::drop1(fit, test = "F"), error = function(e) NULL)
    if (is.null(tab)) return(stats::setNames(rep(NA_real_, length(labs)), labs))
    col <- grep("^Pr\\(", names(tab), value = TRUE)
    out <- stats::setNames(rep(NA_real_, length(labs)), labs)
    hit <- intersect(labs, rownames(tab))
    if (length(col) && length(hit)) out[hit] <- tab[hit, col[[1L]]]
    return(out)
  }
  asg <- attr(stats::model.matrix(fit), "assign")
  p <- vapply(seq_along(labs), function(k) {
    j <- which(asg == k)
    if (!length(j)) return(NA_real_)
    .pv_wald_term(fit, j)
  }, numeric(1), USE.NAMES = FALSE)
  stats::setNames(p, labs)
}

# The driver. Alternates a forward step and a backward step from an
# INTERCEPT-ONLY base until neither moves.
#
# WHY IT STARTS EMPTY. PROC's SELECTION=STEPWISE begins with no explanatory
# variables and adds. The code this replaces handed stats::step() the FULL
# model, which begins at the full model and drops -- a different algorithm that
# can settle on a different set. That was never registered as a divergence
# because nobody noticed it under the larger AIC one.
#
# WHY forward-then-backward, every step. That is the "stepwise" in
# SELECTION=STEPWISE: a term admitted early can become redundant once a
# correlated one enters, and must be able to leave again. Forward-only is
# SELECTION=FORWARD, which is a different option.
.pv_stepwise <- function(fit, data, sle, sls, max_steps, enter, remove) {
  scope <- attr(stats::terms(fit), "term.labels")
  # `data = data` on every update(), for the reason .pv_enter_p() documents.
  current <- tryCatch(
    stats::update(fit, stats::as.formula(". ~ 1"), data = data),
    error = function(e) NULL
  )
  if (is.null(current)) return(fit)
  # coxph's model.matrix/model.frame re-derive `data` from the formula's OWN
  # environment rather than the caller's frame, and update() keeps
  # propagating the environment `fit` was originally created in -- not this
  # function's. Repointing it here to .pv_stepwise's own frame is what makes
  # `data = data` above actually reach a later .pv_remove_p() call for coxph;
  # lm/glm re-derive `data` from the call itself and are unaffected.
  environment(current$terms) <- environment()

  budget <- if (isTRUE(max_steps > 0)) as.integer(max_steps) else
    max(1000L, 10L * length(scope))
  used <- 0L

  # SAS stops when the term about to enter is the one just removed. Without
  # that guard, any screen with sle > sls oscillates -- a term enters on its
  # entry p-value, fails the stricter stay threshold, leaves, and is
  # immediately the best candidate again -- and only the step budget ends it,
  # leaving whichever half of the cycle the budget happened to stop on.
  just_removed <- NA_character_

  repeat {
    moved <- FALSE

    # Forward: the most significant candidate enters if it clears sle.
    inside <- attr(stats::terms(current), "term.labels")
    cand <- setdiff(scope, inside)
    if (length(cand) && used < budget) {
      p <- vapply(cand, function(v) .pv_enter_p(current, v, data, enter),
                  numeric(1), USE.NAMES = FALSE)
      ok <- which(!is.na(p) & p <= sle)
      if (length(ok)) {
        best <- cand[[ok[[which.min(p[ok])]]]]
        if (identical(best, just_removed)) break
        nxt <- tryCatch(
          stats::update(current,
                        stats::as.formula(paste(". ~ . +", best)),
                        data = data),
          error = function(e) NULL
        )
        if (!is.null(nxt)) {
          current <- nxt
          environment(current$terms) <- environment()
          used <- used + 1L
          moved <- TRUE
          just_removed <- NA_character_
        }
      }
    }

    # Backward: the least significant term leaves if it fails sls.
    inside <- attr(stats::terms(current), "term.labels")
    if (length(inside) && used < budget) {
      p <- .pv_remove_p(current, remove)
      ok <- which(!is.na(p) & p > sls)
      if (length(ok)) {
        worst <- names(p)[[ok[[which.max(p[ok])]]]]
        nxt <- tryCatch(
          stats::update(current,
                        stats::as.formula(paste(". ~ . -", worst)),
                        data = data),
          error = function(e) NULL
        )
        if (!is.null(nxt)) {
          current <- nxt
          environment(current$terms) <- environment()
          used <- used + 1L
          moved <- TRUE
          just_removed <- worst
        }
      }
    }

    if (!moved || used >= budget) break
  }
  current
}
