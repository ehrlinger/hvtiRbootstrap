# Does the new stepwise break the pool^3.7 curve? #31 measured stats::step()
# at 0.2s per fit over 10 candidates and 188.3s over 80 -- a log-log slope of
# 3.72, extrapolating to ~54 minutes per fit at the 172 candidates a real
# screen offers, and about 450 hours at n_rep = 500.
#
# THE EXPONENT IS THE NUMBER, not any single timing: a constant-factor win
# would leave 172 candidates just as unreachable. Synthetic data only.
suppressMessages(devtools::load_all("."))

bench1 <- function(p, n = 2000, seed = 1) {
  set.seed(seed)
  d <- as.data.frame(matrix(rnorm(n * p), n, p))
  names(d) <- paste0("x", seq_len(p))
  d$y <- rbinom(n, 1, plogis(1.2 * d$x1 - 0.8 * d$x2))
  f <- stats::as.formula(paste("y ~", paste(names(d)[1:p], collapse = " + ")))
  t0 <- proc.time()[["elapsed"]]
  invisible(fit_logistic(d, f, list(method = "stepwise", sle = 0.10,
                                    sls = 0.05, max_steps = 0)))
  proc.time()[["elapsed"]] - t0
}

pools <- c(10, 20, 40, 80, 172)
secs <- vapply(pools, bench1, numeric(1))
print(data.frame(candidates = pools, seconds = round(secs, 2)))

ok <- secs > 0
slope <- stats::coef(stats::lm(log(secs[ok]) ~ log(pools[ok])))[[2]]
cat(sprintf("\nlog-log slope: %.2f  (stats::step() measured 3.72)\n", slope))
cat(sprintf("implied at n_rep = 500, 172 candidates: %.1f hours\n",
            500 * secs[length(secs)] / 3600))
