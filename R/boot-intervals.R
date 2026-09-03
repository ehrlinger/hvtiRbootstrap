# The percentile points every bn.* macro asks PROC STDIZE for, and the names it
# gives them. 16 and 84 are the 68% interval -- plus or minus one standard
# error, to two figures -- and 2.5/97.5 the 95%.
#
# COVERAGE LIVES IN THE COLUMN NAME. Not one macro in the family takes a
# coverage level: they hardcode PCTLPTS and return both bands, distinguished by
# name. That is stronger than a `conf` argument, because a renderer selects a
# column rather than reading a field it might forget, and a function that takes
# no level cannot be handed 95 where it wanted 0.95.
#
# `median` is named for what it is. %BNMNR calls it MN_RES, which reads as a
# mean; it is PCTLPTS=50. The misnomer is not inherited.
.ci_points <- c(cll_p95 = 0.025, cll_p68 = 0.16, median = 0.50,
                clu_p68 = 0.84, clu_p95 = 0.975)

# One row per quantity, percentiles taken down the replicates.
#
# THE BAND IS POINTWISE. Each column is summarised independently, which is what
# %BNMNR does -- transpose, one PROC STDIZE, transpose back. It is not a
# simultaneous band for a curve drawn through the columns, and the roxygen on
# boot_predict_ci() says so.
#
# type = 4 is SAS PCTLDEF=1, the weighted average at x_(np). R's default is
# type 7 and disagrees: on 1..100 it puts P2.5 at 3.475 rather than 2.5.
.interval_table <- function(m) {
  if (!is.matrix(m) || !is.numeric(m)) {
    stop("`m` must be a numeric matrix of replicate estimates.", call. = FALSE)
  }
  if (is.null(colnames(m))) {
    stop("`m` must have column names, one per estimated quantity.",
         call. = FALSE)
  }
  if (anyNA(m)) {
    stop("`m` has missing estimates. On this branch a replicate either ",
         "estimates every quantity or is discarded, so a missing value here ",
         "would narrow a band rather than record a choice.", call. = FALSE)
  }

  # unname() because quantile() labels its result "2.5%", "16%", ... and
  # vapply compares names against FUN.VALUE.
  q <- vapply(seq_len(ncol(m)), function(j) {
    unname(stats::quantile(m[, j], .ci_points, type = 4))
  }, numeric(length(.ci_points)))
  out <- data.frame(parameter = colnames(m), stringsAsFactors = FALSE)
  for (i in seq_along(.ci_points)) {
    out[[names(.ci_points)[i]]] <- unname(q[i, ])
  }
  rownames(out) <- NULL
  out
}
