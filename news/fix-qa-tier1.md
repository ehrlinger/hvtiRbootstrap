* `boot_pool_chunks()` pools `boot_bag()` output. It could not before: the bag
  recorded its engine as `engine` and carried no `max_steps`, and the pool
  refused both as unrecorded. `boot_bag()` now writes the screen's full
  definition -- `engine_sha` (the commit, `NA` when the installer recorded
  none), `method`, `max_steps`, `fraction`, `resampled` and `rng_kind` -- and
  records `slentry`, `slstay` and `max_steps` as `NA` under
  `select = "none"`, where no selection ran. `boot_validate()` accepts that
  `NA` only on such a bag.
* `boot_pool_chunks()` runs `boot_validate()` on every chunk first, naming the
  chunk and field rather than failing inside `vapply()`, and refuses chunks
  that disagree on the model -- the `fitter` (named, or an md5 of a custom
  fitter's source) or the `formula`, both now recorded by `boot_select()` and
  `boot_bag()` -- or on `method` or `fraction`. A linear and a logistic screen
  of the same data used to pool, averaging slopes with log-odds. A runner chunk that records neither
  is read as `"stepwise"` and `1`, so hazard-runner chunks still pool.
* A run where more than 5% of draws fail now warns, in `boot_select()` and
  `boot_predict_ci()`, and `boot_health()` fails its "Replicates that failed"
  row above that rate. Redrawn replicates make the result conditional on
  estimability; both help pages now say so.
* `fit_cox()` discards a fit that ran out of iterations, as `fit_logistic()`
  discards one that did not converge.
* `boot_select()` validates `sle`, `sls`, `max_steps` and `fitter`. `sle = NA`
  used to give a silently empty screen. A fitter returning an unnamed or
  non-numeric value is now an error naming the contract.
* `boot_select()` no longer seeds a phantom column for a factor when a term
  (`poly()`, `splines::ns()`) cannot be built on zero rows, and records
  `RNGkind()` and the package commit in `$control`. `boot_predict_ci()`
  records both too.
