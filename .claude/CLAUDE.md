# hvtiRbootstrap — repo context

## Documentation reader — default persona

**The CORR biostatistician, bilingual in R and SAS.** They already run
`%bootreg`, `%SUMBOOT` and `%cluster`. Write for that person:

- **Anchor to the macro.** Name the macro a function ports and the argument it
  corresponds to (`n_rep` is `RESAMPL=`, `fraction` is `FRACTION=`). This reader
  reaches for the R function because they know the SAS one.
- **Don't gloss `%bootreg`, and don't gloss base R.** They know both. Explaining
  either wastes their time.
- **Be explicit where R and SAS disagree**, because they will compare outputs.
  Every divergence carries a register entry (D1–D3), roxygen that says so, and a
  test. See `docs/plans/2026-08-14-selection-core.md`.
- **Say what is parity-tested and what is not.** `boot_summary()` and
  `boot_clusters()` are exact; resampling and model fitting are not. The spec's
  parity table is the source of truth.

This is persona (a) from `~/Documents/ObsidianVault/memory/writing-reader-profile.md`
with persona (c)'s bilingual anchor. Note for whoever maintains that file: (c) is
titled "External R user migrating from SAS", and the *external* half does not fit
here — the CORR team is internal and knows the macro library better than most
external readers ever will. Likewise `memory/writing-context.md` scopes itself to
the graphics ecosystem (hvtiPlotR, ggRandomForests, TemporalHazard,
hvtiGraphics) and does not yet mention the macro-migration packages.

## Voice

Follow `ehrlinger-writing`. Narrative register for `@description`/`@details` and
the README; Terse for `@param`/`@return` and NEWS bullets. Error and warning
strings state the condition plainly and are not in scope for the voice.

## Constraints

- **No cohort data, ever.** All fixtures and examples are synthetic. This corpus
  has a PHI history.
- **ASCII only** in R source string literals; use `\uXXXX` if a symbol is needed.
- **Version stays at 0.1.0** until the maintainer cuts a release. Never roll the
  minor or major digit.
- Examples must run without `survival` installed — guard with
  `requireNamespace()`, since it is in Suggests.
