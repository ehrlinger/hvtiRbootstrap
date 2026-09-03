test_that(".boot_resample keeps n_rep results and counts every attempt", {
  # The %DO %WHILE(&SAMPLE<&RESAMPL) loop: a failed draw is redrawn in place
  # and does not consume one of the n_rep, so n_rep counts VALID results while
  # n_attempts counts draws. Both macros report both.
  i <- 0L
  draw <- function() {
    i <<- i + 1L
    i
  }
  # Every third draw fails.
  fit <- function(d) if (d %% 3L == 0L) NULL else d

  r <- .boot_resample(draw, fit, n_rep = 4L, max_attempts = 100L,
                      caller = "x", noun = "results", hint = "")

  expect_length(r$results, 4L)
  expect_equal(unlist(r$results), c(1, 2, 4, 5))
  # Draws 1, 2, 4, 5 succeed; draw 3 fails and is redrawn without counting
  # toward n_rep. The loop exits the instant the 4th result is kept, so the
  # 5th draw is the last attempt spent -- there is no 6th.
  expect_equal(r$n_attempts, 5L)
})

test_that(".boot_resample stops at max_attempts and says what it managed", {
  # Ours, not the macro's: %bootreg's loop advances only on success, so a model
  # that fails on every replicate never terminates. Survivable in a batch job
  # with an operator watching the log; an undiagnosable hang under R CMD check.
  expect_error(
    .boot_resample(function() 1, function(d) NULL, n_rep = 10L,
                   max_attempts = 25L, caller = "boot_select",
                   noun = "models", hint = "Check the data."),
    "gave up after 25 attempts with 0 valid models of 10 requested"
  )
})

test_that(".boot_resample's message carries the caller's own wording", {
  # boot_select() says "models"; the interval branch says "replicates". A
  # shared loop with one hardcoded noun would make one of them wrong.
  expect_error(
    .boot_resample(function() 1, function(d) NULL, n_rep = 2L,
                   max_attempts = 3L, caller = "boot_predict_ci",
                   noun = "replicates", hint = "Check the statistic."),
    "`boot_predict_ci\\(\\)` gave up after 3 attempts with 0 valid replicates"
  )
})

test_that(".boot_resample forces draw() even when fit() never touches it", {
  # fit(draw()) would pass draw() to fit as a promise: a fit whose NULL path
  # never forces its argument would leave draw() uncalled, and the RNG (or,
  # as here, any side effect draw() has) would not advance for that attempt.
  # The draw must be assigned before the fit so this cannot happen.
  n_calls <- 0L
  draw <- function() {
    n_calls <<- n_calls + 1L
    n_calls
  }
  # Returns NULL on every second call WITHOUT forcing `d`.
  i <- 0L
  fit <- function(d) {
    i <<- i + 1L
    if (i %% 2L == 0L) NULL else d
  }

  r <- .boot_resample(draw, fit, n_rep = 4L, max_attempts = 100L,
                      caller = "x", noun = "results", hint = "")

  expect_equal(n_calls, r$n_attempts)
})

test_that(".boot_resample with max_attempts = Inf does not cap", {
  # The documented way back to the macro's uncapped behaviour.
  i <- 0L
  fit <- function(d) {
    i <<- i + 1L
    if (i < 50L) NULL else i
  }
  r <- .boot_resample(function() 1, fit, n_rep = 1L, max_attempts = Inf,
                      caller = "x", noun = "results", hint = "")

  expect_length(r$results, 1L)
  expect_equal(r$n_attempts, 50L)
})
