#' Aggregate selection frequencies over clusters of correlated variables
#'
#' When several candidate terms measure the same thing - weight and body surface
#' area, say - each one's individual selection frequency understates the
#' cluster's importance, because replicates split between them. This reports how
#' often **at least one** member of a cluster was selected. The R port of
#' `%cluster` (`bootstrap.clusters.sas` in the CORR macro library).
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
#' @seealso [boot_summary()] for the per-variable frequencies, and
#'   [boot_select()], which produces the replicates.
#' @examples
#' set.seed(1)
#' n  <- 300
#' x1 <- rnorm(n)
#' df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1,
#'                  x2 = rnorm(n), noise = rnorm(n))
#'
#' fit <- boot_select(df, y ~ x1 + x2 + noise, fit_linear,
#'                    n_rep = 50, seed = 42)
#'
#' # x1 and x2 stand in for a correlated pair -- weight and body surface area,
#' # say. n_any is not the sum of their individual counts: a replicate that
#' # selected both counts once.
#' boot_clusters(fit, list(size = c("x1", "x2"), noise = "noise"))
#' @export
boot_clusters <- function(x, clusters) {
  m <- if (inherits(x, "boot_selection")) x$coefficients else x
  if (!is.matrix(m) || !is.numeric(m))
    stop("`x` must be a boot_selection object or a numeric matrix.",
         call. = FALSE)
  if (!is.list(clusters) || is.null(names(clusters)) ||
        any(names(clusters) == ""))
    stop("`clusters` must be a named list.", call. = FALSE)
  # The validation loop below indexes with clusters[[nm]], which always returns
  # the FIRST element of a duplicated name. Without this check a repeated
  # cluster name means the later one's members are never validated, and a typo
  # there surfaces downstream as "subscript out of bounds", naming neither the
  # cluster nor the offending term.
  dup <- unique(names(clusters)[duplicated(names(clusters))])
  if (length(dup))
    stop("`clusters` must have unique names; duplicated: ",
         paste(dup, collapse = ", "), ".", call. = FALSE)

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
