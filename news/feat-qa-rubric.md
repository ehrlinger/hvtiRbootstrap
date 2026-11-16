* `boot_select()` and `boot_predict_ci()` take `n_boot` for the number of
  valid replicates, the hvtiR family's name for it. `n_rep` still works for
  one release and warns once per session; giving both is an error. The
  result's `$n_rep` field is unchanged.
* `boot_select()`, `boot_predict_ci()` and `boot_bag()` carry the hvtiR
  family's shared provenance record in `$provenance`: `package`, `version`,
  `sha`, `method`, `seed`, `rng_kind` and `time`, taken when the draw began.
  A bag built from a screen that predates the record gets `NA` for what the
  screen cannot tell it.
* Errors a caller may want to catch carry a condition class:
  `hvtiRbootstrap_invalid_bag` (`boot_validate()`),
  `hvtiRbootstrap_pool_refused` (`boot_pool_chunks()`),
  `hvtiRbootstrap_bag_refused` (`boot_bag()`),
  `hvtiRbootstrap_attempts_exhausted` (the replicate budget ran out) and
  `hvtiRbootstrap_bad_argument`. The deprecation warning is
  `hvtiRbootstrap_deprecated`. Messages are unchanged.
