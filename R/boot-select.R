#' Build a model by bootstrap resampling
#'
#' The R port of `%bootreg` (`bootstrap.models.sas` in the CORR macro library).
#' Fits `fitter` on each of `n_rep` bootstrap replicates and records the
#' coefficients each model kept.
#'
#' A term the model did not select is `NA` in that replicate's row. That
#' missingness is the whole design: [boot_summary()] counts non-missing values
#' down a column, so `n` *is* the number of replicates that chose the term. Do
#' not fill those gaps with zero.
#'
#' `fitter` is what `PROC=` was. Adding a model family means writing a fitter,
#' not another pipeline.
#'
#' @param data A data frame.
#' @param formula Model formula offering the candidate terms.
#' @param fitter A fitter such as [fit_logistic()], [fit_linear()] or
#'   [fit_cox()]. `%bootreg` equivalent: `PROC=`.
#' @param n_rep Number of **valid** models to generate (`%bootreg` `RESAMPL=`).
#'   Replicates whose fit fails are redrawn and do not count, matching the
#'   macro's `&regrc` check.
#' @param fraction Fraction of `nrow(data)` to draw per replicate
#'   (`%bootreg` `FRACTION=`). **Divergence:** the macro documents this
#'   parameter but never applies it - it computes `ds_size * fraction`, prints
#'   it, and then always draws `ds_size` rows. This implementation applies it.
#'   Pass `fraction = 1` (the default) to match SAS behaviour exactly.
#' @param select `"stepwise"` or `"none"` (`%bootreg` `SELECT=`/`FIXED=`).
#' @param sle,sls Entry and retention criteria (`%bootreg` `SLE=`, `SLS=`).
#'   Carried for interface fidelity; R's [stats::step()] selects on AIC, so
#'   these do not reproduce SAS's p-value thresholds term for term. Model
#'   fitting is not parity-tested - see the package's design spec.
#' @param max_steps Maximum selection steps (`%bootreg` `MAXSTEP=`). `0` means
#'   no restriction, implemented as a budget scaled to the model - ten passes
#'   over the candidate terms, floored at 1000 - which no realistic model
#'   reaches. It is a budget rather than a truly unbounded count because
#'   [stats::step()] pre-allocates a list of that length.
#' @param max_attempts Budget of resampling attempts before giving up.
#'   **Divergence:** `%bootreg` has no such cap - its loop advances only on a
#'   successful fit, so a model that fails on every replicate never terminates.
#'   That is survivable in a batch job with an operator watching the log; under
#'   `R CMD check` it is an unbounded hang with no diagnostic. Exhausting the
#'   budget raises an error reporting how many valid models were obtained. Pass
#'   `Inf` to restore the macro's uncapped behaviour.
#' @param seed Optional integer for reproducibility.
#' @return An object of class `boot_selection`. `$coefficients` is a matrix with
#'   one row per valid replicate and one column per candidate term, `NA` where
#'   the term was not selected. `$control` records the run's own settings --
#'   `method`, `sle`, `sls`, `max_steps`, `fraction`, `seed`, `n_rows`,
#'   `n_terms`, `elapsed_mins` and the `package` version -- so that
#'   [boot_bag()] can build a provenance record from the run rather than from
#'   what a caller retypes. `$call` cannot serve that purpose: `match.call()`
#'   omits every argument left at its default.
#' @seealso [boot_summary()] for the per-variable selection frequencies, and
#'   [boot_clusters()] for the same question asked of a correlated group.
#'   [fit_linear()], [fit_logistic()] and [fit_cox()] are the supplied fitters.
#' @examples
#' set.seed(1)
#' n  <- 300
#' x1 <- rnorm(n)
#' df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1,
#'                  x2 = rnorm(n), noise = rnorm(n))
#'
#' # n_rep is RESAMPL=. It counts VALID models, so a replicate whose fit fails
#' # is redrawn and does not consume one -- the macro's &regrc check.
#' fit <- boot_select(df, y ~ x1 + x2 + noise, fit_linear,
#'                    n_rep = 50, seed = 42)
#' fit
#'
#' # The replicate table itself, one row per model, NA where a term was not
#' # selected. This is what %bootreg writes to OUTEST=.
#' head(fit$coefficients, 3)
#'
#' boot_summary(fit)
#' @export
boot_select <- function(data, formula, fitter, n_rep = 1000, fraction = 1,
                        select = c("stepwise", "none"), sle = 0.10, sls = 0.05,
                        max_steps = 0, max_attempts = 10 * n_rep, seed = NULL) {
  select <- match.arg(select)
  # Seeding is a global side effect, so put the caller's stream back. This runs
  # FIRST, before any argument promise is forced: `data` is often an expression
  # that itself draws (or calls set.seed), and the stream we owe the caller is
  # the one in place when boot_select() was called, not after those side
  # effects. Without a restore, a script that seeds once at the top silently
  # loses reproducibility from the first boot_select(seed = ) call onward.
  #
  # withr rather than a hand-rolled save/restore: assigning .Random.seed back
  # into globalenv() ourselves earns the "assignments to the global
  # environment" NOTE from R CMD check --as-cran, which the house release gate
  # does not accept. withr depends only on base packages.
  if (!is.null(seed)) withr::local_preserve_seed()
  if (!is.data.frame(data) || nrow(data) == 0L)
    stop("`data` must be a data frame with at least one row.", call. = FALSE)
  if (!is.numeric(fraction) || length(fraction) != 1L ||
        is.na(fraction) || fraction <= 0 || fraction > 1)
    stop("`fraction` must be greater than 0 and at most 1.", call. = FALSE)
  # Whole numbers, checked rather than truncated: vector("list", 2.5) quietly
  # gives 2, so a fractional n_rep would silently deliver fewer replicates than
  # asked for. max_attempts is a count too, with Inf as D3's documented escape
  # hatch and therefore the one non-integer value allowed.
  if (!is.numeric(n_rep) || length(n_rep) != 1L || is.na(n_rep) ||
        n_rep < 1 || n_rep != trunc(n_rep) || is.infinite(n_rep))
    stop("`n_rep` must be a positive whole number of replicates.",
         call. = FALSE)
  if (!is.numeric(max_attempts) || length(max_attempts) != 1L ||
        is.na(max_attempts) || max_attempts < n_rep ||
        (is.finite(max_attempts) && max_attempts != trunc(max_attempts)))
    stop("`max_attempts` must be a whole number at least as large as `n_rep`, ",
         "or `Inf`.", call. = FALSE)

  if (!is.null(seed)) set.seed(seed)

  n <- nrow(data)
  draw <- max(1L, round(n * fraction))
  ctrl <- list(method = select, sle = sle, sls = sls, max_steps = max_steps)
  # Candidate columns must be the DUMMY-CODED names the fitters will return,
  # not the formula's term labels. A factor `sex` yields a "sexM" coefficient,
  # so seeding the matrix with "sex" left a column NA in every replicate that
  # boot_summary() then reported as a term selected 0% of the time -- the same
  # phantom-term failure the "(Intercept)" handling below avoids for Cox.
  # Built on a zero-row frame so no model matrix is materialised, and with the
  # response deleted so a Surv() left-hand side is never evaluated.
  terms_all <- tryCatch({
    tt <- stats::delete.response(stats::terms(formula, data = data))
    setdiff(colnames(stats::model.matrix(tt, data[0, , drop = FALSE])),
            "(Intercept)")
  }, error = function(e) {
    attr(stats::terms(formula, data = data), "term.labels")
  })

  fits <- vector("list", n_rep)
  kept <- 0L
  attempts <- 0L
  .t0 <- proc.time()[["elapsed"]]
  # %bootreg's loop: keep resampling until n_rep VALID models exist. A failed
  # fit is redrawn in place and does not count toward n_rep, only toward
  # attempts -- the macro reports both.
  #
  # D3: the budget is ours, not the macro's. %bootreg would spin here forever
  # when no replicate ever fits; that is a hang with no diagnostic under
  # R CMD check, so we stop and say what we managed. max_attempts = Inf is the
  # documented way back to the macro's behaviour.
  while (kept < n_rep) {
    if (attempts >= max_attempts)
      stop("`boot_select()` gave up after ", attempts, " attempts with ",
           kept, " valid models of ", n_rep, " requested. The model could not ",
           "be fitted on most replicates; check the formula and the data, or ",
           "raise `max_attempts`.", call. = FALSE)
    attempts <- attempts + 1L
    idx <- sample.int(n, size = draw, replace = TRUE)
    cf <- fitter(data[idx, , drop = FALSE], formula, ctrl)
    if (is.null(cf)) next
    kept <- kept + 1L
    fits[[kept]] <- cf
  }

  # Columns are the offered terms plus whatever the fitters actually returned.
  # "(Intercept)" is NOT hardcoded: Cox models have none, and manufacturing one
  # would put an all-NA column in every Cox result that boot_summary() would
  # then report as a variable with n = 0.
  seen <- unique(unlist(lapply(fits, names), use.names = FALSE))
  cols <- unique(c(intersect("(Intercept)", seen), terms_all, seen))
  m <- matrix(NA_real_, nrow = n_rep, ncol = length(cols),
              dimnames = list(NULL, cols))
  for (i in seq_len(n_rep)) m[i, names(fits[[i]])] <- fits[[i]]

  # What the run knows about itself. boot_bag() reads this rather than asking
  # its caller to retype it: a bag whose slentry was typed by hand can disagree
  # with the screen it describes, and the provenance table would then report
  # the typed value as though the screen had used it.
  #
  # `call` cannot serve. match.call() omits every argument left at its default,
  # so a run at the default sle = 0.10 records nothing at all about sle.
  #
  # elapsed is this call's own elapsed seconds, in the minutes boot_validate()
  # expects. A chunked run sums them in boot_pool_chunks(), which is why the
  # unit matters here rather than being whatever was convenient.
  control <- list(
    method       = ctrl$method,
    sle          = ctrl$sle,
    sls          = ctrl$sls,
    max_steps    = as.integer(ctrl$max_steps),
    fraction     = fraction,
    seed         = if (is.null(seed)) NA_real_ else as.numeric(seed),
    n_rows       = as.integer(n),
    n_terms      = length(terms_all),
    elapsed_mins = (proc.time()[["elapsed"]] - .t0) / 60,
    package      = as.character(utils::packageVersion("hvtiRbootstrap"))
  )

  new_boot_selection(m, n_rep = as.integer(n_rep),
                     n_attempts = attempts, call = match.call(),
                     control = control)
}
