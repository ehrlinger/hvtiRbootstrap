# hvtiRbootstrap

Bootstrap model building for the HVTI CORR group - the R port of the SAS
`%bootreg` / `%SUMBOOT` / `%cluster` macros.

Fit a model on each of many bootstrap replicates, record which variables
survive selection, and report how often each appeared.

Destination for 31 macro-library files, assigned by the allocation map in
`hvtiRtemplates:specs/2026-08-14-macro-allocation-design.md`. Design and scope:
`docs/specs/2026-08-14-hvtirbootstrap-design.md`.

## Example

```r
library(hvtiRbootstrap)

set.seed(1)
n  <- 300
x1 <- rnorm(n)
df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1,
                 x2 = rnorm(n), noise = rnorm(n))

fit <- boot_select(df, y ~ x1 + x2 + noise, fit_linear,
                   n_rep = 200, seed = 42)

boot_summary(fit)
#>   variable   n   pct ...      <- how often each term survived selection

boot_clusters(fit, list(size = c("x1", "x2")))
#>   cluster n_any pct_any ...   <- how often AT LEAST ONE member survived
```

`n` counts the replicates in which a term was selected, so `pct` reads as a
selection frequency. `boot_clusters()` is not the sum of its members' counts: a
replicate selecting two members counts once.

## Status

Under development. v1 covers the selection core with logistic, linear and Cox
fitters. Hazard and quantile fitters, the bootstrap-CI family, and penalised
selection are each deferred to their own spec.

## Divergence from the SAS macros

This port is **correct first, faithful second**: where the macro's behaviour and
its documented intent disagree, it implements the intent and says so here.

**D1 - `fraction` is applied.** `%bootreg` documents `FRACTION=` but never uses
it: it computes `ds_size * fraction`, prints it, and always draws `ds_size` rows.
`boot_select()` draws `round(n * fraction)`. Pass `fraction = 1` (the default) to
match SAS exactly. **A filed result run with `FRACTION` other than 1.0 was not
subsampled**, so R will disagree with it.

**D2 - stepwise selects on AIC, not p-values.** SAS `SELECTION=STEPWISE` uses
`SLE=`/`SLS=` as p-value thresholds; R's `step()` uses AIC. `sle` and `sls` are
carried for interface fidelity and do not reproduce SAS's selection term for
term. This is why model fitting sits outside the parity claim.

**D3 - the retry loop is capped.** `%bootreg` resamples until it has `RESAMPL`
valid models and never gives up, so a model that fails on every replicate spins
forever. `boot_select()` budgets `max_attempts = 10 * n_rep` and errors with a
diagnostic when it runs out. Pass `max_attempts = Inf` for the macro's
behaviour.

`boot_summary()` and `boot_clusters()` **are** held to exact parity.
