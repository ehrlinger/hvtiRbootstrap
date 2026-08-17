# hvtiRbootstrap

Bootstrap model building for the HVTI CORR group - the R port of the SAS
`%bootreg` / `%SUMBOOT` / `%cluster` macros.

Fit a model on each of many bootstrap replicates, record which variables
survive selection, and report how often each appeared.

Destination for 31 macro-library files, assigned by the allocation map in
`hvtiRtemplates:specs/2026-08-14-macro-allocation-design.md`. Design and scope:
`docs/specs/2026-08-14-hvtirbootstrap-design.md`.

## Status

Under development. v1 covers the selection core with logistic, linear and Cox
fitters. Hazard and quantile fitters, the bootstrap-CI family, and penalised
selection are each deferred to their own spec.
