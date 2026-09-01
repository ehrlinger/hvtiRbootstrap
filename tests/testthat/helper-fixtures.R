# A fixed replicate table with hand-computable answers. Synthetic: no cohort
# data enters this package.
#
#        x1   x2   x3
#   r1  1.0  2.0   NA
#   r2  2.0   NA   NA
#   r3  3.0  4.0   NA
#   r4  4.0   NA   NA
#
# x1: n=4 pct=100 mean=2.5 sd=sd(1:4) min=1 max=4
# x2: n=2 pct=50  mean=3   sd=sd(c(2,4)) min=2 max=4
# x3: n=0 pct=0   mean/sd/min/max all NA
fx_replicates <- function() {
  matrix(
    c(1, 2, 3, 4,
      2, NA, 4, NA,
      NA, NA, NA, NA),
    nrow = 4,
    dimnames = list(NULL, c("x1", "x2", "x3"))
  )
}

# Replicate table where cluster membership matters:
#
#        a1   a2   b1
#   r1  1.0   NA  1.0
#   r2   NA  1.0  1.0
#   r3  1.0  1.0   NA
#   r4   NA   NA   NA
#
# cluster A = {a1, a2}: a1 selected twice, a2 twice, but "at least one of A"
# happens in r1, r2, r3 = 3 replicates, NOT 4. That is the number the
# per-variable summary cannot give you.
fx_cluster_replicates <- function() {
  matrix(
    c(1, NA, 1, NA,
      NA, 1, 1, NA,
      1, 1, NA, NA),
    nrow = 4,
    dimnames = list(NULL, c("a1", "a2", "b1"))
  )
}

# A bag shaped like the one boot_pool_chunks() returns, with hand-computable
# answers. Synthetic: no cohort data enters this package.
#
#   replicate  terms selected
#   1          base, early.age, early.ln_age
#   2          base, early.age
#   3          base, early.ln_age, early.bmi
#   4          base, late.age
#
# Over n_boot = 4: base 4 (100%), early.age 2 (50%), early.ln_age 2 (50%),
# early.bmi 1 (25%), late.age 1 (25%).
#
# The Age concept in the early phase is the union case: its two forms sit at
# 50% each, and "at least one form" happens in replicates 1, 2 and 3 -- 75%,
# not 100%. Replicate 1 took BOTH forms and must count once.
#
# `requested` and `usable` are scalars here so that a test giving them a
# per-phase vector is visibly the variation, not the fixture's own shape.
fx_bag <- function() {
  reps <- data.frame(
    replicate = c(1L, 1L, 1L, 2L, 2L, 3L, 3L, 3L, 4L, 4L),
    parameter = c("base", "early.age", "early.ln_age",
                  "base", "early.age",
                  "base", "early.ln_age", "early.bmi",
                  "base", "late.age"),
    estimate  = c(1.0, 0.5, 0.4,
                  1.1, 0.6,
                  0.9, 0.3, 0.2,
                  1.2, 0.7),
    stringsAsFactors = FALSE
  )
  summ <- data.frame(
    parameter = c("base", "early.age", "early.ln_age", "early.bmi",
                  "late.age"),
    n         = c(4L, 2L, 2L, 1L, 1L),
    pct       = c(100, 50, 50, 25, 25),
    stringsAsFactors = FALSE
  )
  list(
    n_boot       = 4L,
    n_chunks     = 2L,
    seed         = "101, 202",
    seeds        = c(101, 202),
    slentry      = 0.07,
    slstay       = 0.05,
    base_params  = "base",
    requested    = 4L,
    usable       = 3L,
    n_rows       = 500L,
    elapsed_mins = 120,
    free_sd      = stats::sd(c(1.0, 1.1, 0.9, 1.2)),
    th_sha       = "deadbeef",
    manifest     = list(sha256 = "abc123"),
    boot         = list(replicates = reps, summary = summ,
                        n_success = 4L, n_failed = 0L)
  )
}

# A bag with prescribed selection counts, for tests that need a denominator
# larger than fx_bag()'s four. Term `nm` is selected in the FIRST
# counts[[nm]] replicates, so its selection frequency is exactly
# counts[[nm]] / n_boot and its Monte-Carlo error is hand-computable. The base
# parameter is selected in every replicate, with an estimate that varies, so
# the screen reads as healthy.
fx_bag_counts <- function(counts, n_boot = 400L) {
  n_boot <- as.integer(n_boot)
  base_est <- seq_len(n_boot) / n_boot
  rows <- list(data.frame(replicate = seq_len(n_boot), parameter = "base",
                          estimate = base_est, stringsAsFactors = FALSE))
  for (nm in names(counts)) {
    k <- counts[[nm]]
    if (k > 0L) {
      rows[[length(rows) + 1L]] <- data.frame(
        replicate = seq_len(k), parameter = nm, estimate = 1,
        stringsAsFactors = FALSE
      )
    }
  }
  reps <- do.call(rbind, rows)
  reps <- reps[order(reps$replicate), , drop = FALSE]
  rownames(reps) <- NULL

  n <- c(base = n_boot, unlist(counts))
  bag <- fx_bag()
  bag$n_boot <- n_boot
  bag$free_sd <- stats::sd(base_est)
  bag$boot$replicates <- reps
  bag$boot$summary <- data.frame(parameter = names(n), n = as.integer(n),
                                 pct = 100 * n / n_boot,
                                 stringsAsFactors = FALSE)
  bag$boot$n_success <- n_boot
  bag
}

# The term-splitting rule a multiphase hazard screen passes: `early.age` is
# the early phase's screening decision about `age`. Deliberately NOT the
# package's default -- a logistic screen has no phases at all.
fx_phase <- function(term) sub("[.].*$", "", term)
