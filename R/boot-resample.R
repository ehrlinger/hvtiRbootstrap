# The valid-model loop, shared by both branches.
#
# WHY IT IS SHARED. %bootreg and %BNMNR are different macros doing different
# jobs -- one selects variables, one bands an estimate -- but their resampling
# loops are the same loop: draw, fit, keep on success, and on failure redraw in
# place without the failure counting toward n_rep. Both counts are tracked and
# both are reported: RESAMPL= counts VALID results, while every draw -- failed
# ones included -- counts toward n_attempts, which is what the macros print as
# the total number of resamplings. Writing it twice would let the two copies
# drift, and the drift would be invisible because each branch's tests would
# still pass.
#
# WHY caller/noun/hint RATHER THAN ONE MESSAGE. boot_select() gave up "with 0
# valid models"; the interval branch gives up with 0 valid replicates. A test
# pins boot_select()'s wording, and a hardcoded noun would make one caller's
# error describe the other's job.
#
# The attempt budget is D3, ours rather than the macro's: %bootreg's loop
# advances only on a successful fit, so a model that fails on every replicate
# never terminates. `Inf` restores that.
.boot_resample <- function(draw, fit, n_rep, max_attempts, caller, noun,
                           hint) {
  kept <- vector("list", n_rep)
  n_kept <- 0L
  attempts <- 0L
  while (n_kept < n_rep) {
    if (attempts >= max_attempts) {
      stop("`", caller, "()` gave up after ", attempts, " attempts with ",
           n_kept, " valid ", noun, " of ", n_rep, " requested. ", hint,
           call. = FALSE)
    }
    attempts <- attempts + 1L
    # Assigned rather than inlined as fit(draw()): inlining passes draw() to
    # fit as a lazy PROMISE, so a fitter whose NULL path never touches its
    # argument would never force it, the RNG would never advance for that
    # attempt, and the same seed would then yield different replicates than
    # this loop drew before the refactor. Assignment forces the draw up
    # front, every attempt, regardless of what fit() does with it.
    d <- draw()
    r <- fit(d)
    if (is.null(r)) next
    n_kept <- n_kept + 1L
    kept[[n_kept]] <- r
  }
  list(results = kept, n_attempts = attempts)
}
