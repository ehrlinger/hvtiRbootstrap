# hvtiRbootstrap 0.1.0

* Initial development version. Selection core only: `boot_select()`,
  `boot_summary()`, `boot_clusters()`, with logistic, linear and Cox fitters.
* `boot_select()` no longer reports a factor predictor as never selected. Its
  candidate columns are the dummy-coded coefficient names the fitters return,
  so a factor `sex` appears once as `sexM` rather than also as an all-`NA`
  `sex` column with `n = 0`.
* `boot_select()` restores the caller's RNG state on exit, so passing `seed`
  no longer changes later random draws in the calling script.
* The fitters keep a converged model that merely warned. Previously any
  warning - notably `"fitted probabilities numerically 0 or 1"` on a
  quasi-separated replicate - discarded the replicate, which biased selection
  frequencies against strong predictors. Errors and logistic non-convergence
  still reject.
* A model that selected no terms is now a valid replicate rather than a failed
  fit. This only affected Cox, which has no intercept to survive selection,
  and it had been inflating every variable's reported frequency.
* `boot_clusters()` rejects duplicated cluster names, and `boot_summary()`
  rejects a matrix without column names, instead of failing later with an
  unrelated message.
