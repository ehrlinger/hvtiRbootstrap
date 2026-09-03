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
  bigger <- tryCatch(
    stats::update(fit, stats::as.formula(paste(". ~ . +", term)),
                  data = data),
    error = function(e) NULL, warning = function(w) NULL
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
