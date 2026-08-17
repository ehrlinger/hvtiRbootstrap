#' Aggregate selection frequencies over clusters of correlated variables
#'
#' When several candidate terms measure the same thing - weight and body surface
#' area, say - each one's individual selection frequency understates the
#' cluster's importance, because replicates split between them. This reports how
#' often **at least one** member of a cluster was selected. The R port of
#' `%cluster` (`~/Documents/macro.library/bootstrap.clusters.sas`).
#'
#' `n_any` is not the sum of the members' individual counts: a replicate that
#' selected two members counts once.
#'
#' The macro also tabulates its `ncluster` counter - the full distribution of
#' *how many* members appeared together in a replicate. That is deliberately not
#' reproduced: the per-variable frequencies are already [boot_summary()]'s job,
#' and "at least one" is the number neither function can derive from the other.
#'
#' @param x A `boot_selection` from [boot_select()], or a numeric matrix with
#'   one row per replicate and one column per term.
#' @param clusters Named list mapping a cluster name to its member terms.
#' @return A data frame with columns `cluster`, `n_any`, `pct_any`, `members`,
#'   sorted by descending `n_any`.
#' @seealso [boot_summary()] for the per-variable frequencies.
#' @export
boot_clusters <- function(x, clusters) {
  m <- if (inherits(x, "boot_selection")) x$coefficients else x
  if (!is.matrix(m) || !is.numeric(m))
    stop("`x` must be a boot_selection object or a numeric matrix.",
         call. = FALSE)
  if (!is.list(clusters) || is.null(names(clusters)) ||
        any(names(clusters) == ""))
    stop("`clusters` must be a named list.", call. = FALSE)

  for (nm in names(clusters)) {
    missing <- setdiff(clusters[[nm]], colnames(m))
    if (length(missing))
      stop("cluster `", nm, "` names terms not present in the replicates: ",
           paste(missing, collapse = ", "), ".", call. = FALSE)
  }

  n_rep <- nrow(m)
  any_hit <- vapply(clusters, function(members) {
    sub <- m[, members, drop = FALSE]
    sum(rowSums(!is.na(sub)) > 0L)
  }, integer(1))

  out <- data.frame(
    cluster = names(clusters),
    n_any   = as.integer(any_hit),
    pct_any = 100 * as.integer(any_hit) / n_rep,
    members = vapply(clusters, paste, character(1), collapse = ", "),
    stringsAsFactors = FALSE
  )
  out <- out[order(-out$n_any, out$cluster), , drop = FALSE]
  rownames(out) <- NULL
  out
}
