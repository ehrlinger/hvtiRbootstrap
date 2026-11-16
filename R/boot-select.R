#' Build a model by bootstrap resampling
#'
#' The R port of `%bootreg` (`bootstrap.models.sas` in the CORR macro library).
#' Fits `fitter` on each of `n_boot` bootstrap replicates and records the
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
#' @param n_boot Number of **valid** models to generate (`%bootreg`
#'   `RESAMPL=`).
#'   Replicates whose fit fails are redrawn and do not count, matching the
#'   macro's `&regrc` check. That makes the result **conditional on
#'   estimability**: the replicates kept are those on which the model could
#'   be fitted. When more than 5% of draws fail the run warns, and
#'   [boot_health()] flags the rate.
#' @param n_rep Deprecated name for `n_boot`, renamed under the hvtiR API
#'   rubric. It still works for one release and warns once per session.
#' @param fraction Fraction of `nrow(data)` to draw per replicate
#'   (`%bootreg` `FRACTION=`). **Divergence:** the macro documents this
#'   parameter but never applies it - it computes `ds_size * fraction`, prints
#'   it, and then always draws `ds_size` rows. This implementation applies it.
#'   Pass `fraction = 1` (the default) to match SAS behaviour exactly.
#' @param select `"stepwise"` or `"none"` (`%bootreg` `SELECT=`/`FIXED=`).
#' @param sle,sls Entry and retention p-value thresholds (`%bootreg` `SLE=`,
#'   `SLS=`). Each fitter pins its own entry and removal test to match its
#'   `PROC=` - see [fit_linear()], [fit_logistic()] and [fit_cox()] - so `sle`
#'   and `sls` are exactly what they mean in the job being ported. Model
#'   fitting is still not parity-tested - see the package's design spec - but
#'   these two arguments now select rather than only being recorded.
#'   **Divergence:** candidates are flat term labels, not a hierarchy, and
#'   [fit_linear()]'s removal test respects marginality while
#'   [fit_logistic()]'s and [fit_cox()]'s Wald removal test does not - so a
#'   screen can keep an interaction without either main effect on the latter
#'   two, which `PROC LOGISTIC`'s default `HIERARCHY=SINGLE` would not do.
#'   Not implemented; see D5 in the README's divergence register.
#' @param max_steps Maximum selection steps (`%bootreg` `MAXSTEP=`). `0` means
#'   no restriction, implemented as a budget scaled to the model - ten passes
#'   over the candidate terms, floored at 1000 - which no realistic model
#'   reaches. It bounds the p-value stepwise driver's forward/backward loop
#'   (`.pv_stepwise()` in `R/stepwise.R`) rather than leaving it genuinely
#'   unbounded.
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
#'   `n_terms`, `elapsed_mins`, the `package` version, its commit `sha`
#'   (`NA` when the installer recorded none), `rng_kind`, the `fitter`
#'   (`"fit_linear"`, `"fit_logistic"`, `"fit_cox"`, or an md5 of a custom
#'   fitter's source) and the deparsed `formula` -- so that a bag
#'   builder [boot_bag()] can take a provenance record from
#'   the run rather than from what a caller retypes. `$call` cannot serve
#'   that purpose: `match.call()` omits every argument left at its default.
#'   `$provenance` is the hvtiR family's shared provenance record (`package`,
#'   `version`, `sha`, `method`, `seed`, `rng_kind`, `time`), taken when the
#'   draw began, followed by this package's `fitter` and `formula`. The
#'   replicate count stays in `$n_rep`.
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
#' # n_boot is RESAMPL=. It counts VALID models, so a replicate whose fit fails
#' # is redrawn and does not consume one -- the macro's &regrc check.
#' fit <- boot_select(df, y ~ x1 + x2 + noise, fit_linear,
#'                    n_boot = 50, seed = 42)
#' fit
#'
#' # The replicate table itself, one row per model, NA where a term was not
#' # selected. This is what %bootreg writes to OUTEST=.
#' head(fit$coefficients, 3)
#'
#' boot_summary(fit)
#' @export
boot_select <- function(data, formula, fitter, n_boot = 1000, fraction = 1,
                        select = c("stepwise", "none"), sle = 0.10, sls = 0.05,
                        max_steps = 0, max_attempts = 10 * n_boot,
                        seed = NULL, n_rep) {
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
  if (!missing(n_rep)) {
    if (!missing(n_boot))
      .abort("boot_select(): give `n_boot` only; `n_rep` is its ",
             "deprecated name.", class = "bad_argument")
    .deprecated_arg("boot_select", "n_rep", "n_boot")
    n_boot <- n_rep
  }
  if (!is.data.frame(data) || nrow(data) == 0L)
    stop("`data` must be a data frame with at least one row.", call. = FALSE)
  if (!is.numeric(fraction) || length(fraction) != 1L ||
        is.na(fraction) || fraction <= 0 || fraction > 1)
    stop("`fraction` must be greater than 0 and at most 1.", call. = FALSE)
  # Whole numbers, checked rather than truncated: vector("list", 2.5) quietly
  # gives 2, so a fractional n_boot would silently deliver fewer replicates
  # than asked for. max_attempts is a count too, with Inf as D3's documented
  # escape hatch and therefore the one non-integer value allowed.
  if (!is.numeric(n_boot) || length(n_boot) != 1L || is.na(n_boot) ||
        n_boot < 1 || n_boot != trunc(n_boot) || is.infinite(n_boot))
    stop("`n_boot` must be a positive whole number of replicates.",
         call. = FALSE)
  if (!is.numeric(max_attempts) || length(max_attempts) != 1L ||
        is.na(max_attempts) || max_attempts < n_boot ||
        (is.finite(max_attempts) && max_attempts != trunc(max_attempts)))
    stop("`max_attempts` must be a whole number at least as large as ",
         "`n_boot`, ",
         "or `Inf`.", call. = FALSE)

  if (!is.function(fitter))
    stop("`fitter` must be a function such as fit_linear, fit_logistic or ",
         "fit_cox, found ", class(fitter)[1L], ".", call. = FALSE)
  # NA here is not a looser threshold, it is no threshold: every p-value
  # comparison against it is NA, the step accepts nothing, and the screen
  # returns an empty selection that reads as a finding.
  levels <- list(sle = sle, sls = sls)
  for (nm in names(levels)) {
    v <- levels[[nm]]
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0 || v > 1)
      stop("`", nm, "` must be a single p-value threshold between 0 and 1.",
           call. = FALSE)
  }
  if (!is.numeric(max_steps) || length(max_steps) != 1L ||
        is.na(max_steps) || max_steps < 0 || max_steps != trunc(max_steps) ||
        is.infinite(max_steps))
    stop("`max_steps` must be a whole number of steps, 0 for no ",
         "restriction.", call. = FALSE)

  if (!is.null(seed)) set.seed(seed)
  # Built at the draw, not later: RNGkind() and the time are facts about now.
  # The model follows the seven common fields, as $control and the bag carry
  # it: a record that cannot say which model ran cannot tell two screens of
  # the same data apart.
  prov <- .hvti_provenance(select, seed, fitter = .fitter_id(fitter),
                           formula = paste(deparse(formula,
                                                   width.cutoff = 500L),
                                           collapse = " "))

  n <- nrow(data)
  n_draw <- max(1L, round(n * fraction))
  ctrl <- list(method = select, sle = sle, sls = sls, max_steps = max_steps)
  # Candidate columns must be the DUMMY-CODED names the fitters will return,
  # not the formula's term labels. A factor `sex` yields a "sexM" coefficient,
  # so seeding the matrix with "sex" left a column NA in every replicate that
  # boot_summary() then reported as a term selected 0% of the time -- the same
  # phantom-term failure the "(Intercept)" handling below avoids for Cox.
  # Built on a zero-row frame so no model matrix is materialised, and with the
  # response deleted so a Surv() left-hand side is never evaluated.
  #
  # Some terms cannot be built on zero rows (poly(), splines::ns()), so the
  # fallback is the full frame, built once. It is NOT the formula's term
  # labels: those are the undummied names, and a factor `sex` seeded as a
  # column is the phantom described above. If even the full frame fails, the
  # columns are whatever the fitters return.
  tt <- stats::delete.response(stats::terms(formula, data = data))
  .mm_cols <- function(d) {
    setdiff(colnames(stats::model.matrix(tt, d)), "(Intercept)")
  }
  terms_all <- tryCatch(
    .mm_cols(data[0, , drop = FALSE]),
    error = function(e) {
      tryCatch(.mm_cols(data), error = function(e) character(0))
    }
  )

  .t0 <- proc.time()[["elapsed"]]
  # The loop moved to .boot_resample(), which %BNMNR shares. The comments that
  # were here -- why a failed fit is redrawn without counting, and why the
  # attempt budget is ours rather than the macro's -- live there now.
  drawn <- .boot_resample(
    draw = function() {
      data[sample.int(n, size = n_draw, replace = TRUE), , drop = FALSE]
    },
    fit  = function(d) .check_fitter_result(fitter(d, formula, ctrl)),
    n_rep = n_boot, max_attempts = max_attempts,
    caller = "boot_select", noun = "models",
    hint = paste0("The model could not be fitted on most replicates; check ",
                  "the formula and the data, or raise `max_attempts`.")
  )
  fits <- drawn$results
  attempts <- drawn$n_attempts

  # Columns are the offered terms plus whatever the fitters actually returned.
  # "(Intercept)" is NOT hardcoded: Cox models have none, and manufacturing one
  # would put an all-NA column in every Cox result that boot_summary() would
  # then report as a variable with n = 0.
  seen <- unique(unlist(lapply(fits, names), use.names = FALSE))
  cols <- unique(c(intersect("(Intercept)", seen), terms_all, seen))
  m <- matrix(NA_real_, nrow = n_boot, ncol = length(cols),
              dimnames = list(NULL, cols))
  for (i in seq_len(n_boot)) m[i, names(fits[[i]])] <- fits[[i]]

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
  # rng_kind: the same seed under a different RNGkind() is a different
  # stream, so the seed alone does not reproduce a run.
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
    package      = as.character(utils::packageVersion("hvtiRbootstrap")),
    sha          = .package_sha(),
    rng_kind     = RNGkind(),
    # The model itself, so boot_pool_chunks() can refuse to pool a linear
    # screen with a logistic one, or two formulas that happen to offer the
    # same number of candidates. Without these, chunks agreeing on every
    # other gate pooled log-odds with slopes.
    fitter       = prov$fitter,
    formula      = prov$formula
  )

  out <- new_boot_selection(m, n_rep = as.integer(n_boot),
                            n_attempts = attempts, call = match.call(),
                            control = control)
  out$provenance <- prov
  out
}

# A fitter's result is checked once, here, rather than trusted. NULL is the
# failed-replicate signal and passes through. Anything else must be a numeric
# vector with unique names: an unnamed one fails inside `m[i, names(.)]` with
# an error about subscripts that names neither the fitter nor the contract,
# and a duplicated name keeps only the last value, silently.
.check_fitter_result <- function(r) {
  if (is.null(r)) return(NULL)
  nm <- names(r)
  bad_names <- length(r) > 0L &&
    (is.null(nm) || anyNA(nm) || any(nm == "") || anyDuplicated(nm) > 0L)
  if (!is.numeric(r) || bad_names) {
    what <- if (is.numeric(r)) {
      "a numeric vector with missing or duplicated names"
    } else {
      paste0("an object of class ", class(r)[1L])
    }
    stop("`fitter` returned ", what, ". A fitter must return a NAMED ",
         "numeric vector of the coefficients the model kept, or NULL when ",
         "the fit failed. See the fitter contract in ?fit_linear.",
         call. = FALSE)
  }
  r
}

# The commit this package was installed from, when the installer recorded
# one (remotes, pak and devtools write RemoteSha), else NA. A version string
# alone cannot tell two builds of the same version apart.
.package_sha <- function() {
  sha <- utils::packageDescription("hvtiRbootstrap", fields = "RemoteSha")
  if (length(sha) != 1L || is.na(sha) || !nzchar(sha)) NA_character_ else sha
}

# A fitter's identity for the pool gate. The shipped fitters are named; any
# other function is fingerprinted by an md5 of its deparsed source, so two
# different custom fitters disagree. A closure's captured settings are not in
# its source, so two closures differing only there look the same -- a custom
# fitter that is configured that way should differ in its body as well.
.fitter_id <- function(fitter) {
  shipped <- list(fit_linear = fit_linear, fit_logistic = fit_logistic,
                  fit_cox = fit_cox)
  for (nm in names(shipped)) {
    if (identical(fitter, shipped[[nm]], ignore.environment = TRUE)) {
      return(nm)
    }
  }
  f <- tempfile()
  on.exit(unlink(f))
  writeLines(deparse(fitter), f)
  paste0("custom:md5:", unname(tools::md5sum(f)))
}
