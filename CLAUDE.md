@AGENTS.md

# Claude Code specifics

[`AGENTS.md`](AGENTS.md), imported above, is the operational contract and applies in full. It is written
to be tool neutral so that Codex and other agents read the same rules. Only the Claude Code
affordances live here.

## Before you touch code

`AGENTS.md` says to orient before editing. In Claude Code the way to do that is the codemap:
it lives in the Obsidian vault under `Claude/repomaps/` and is read via the `read-codemap`
skill (`/codemap hvtiRbootstrap`). If the codemap looks stale, say so and offer to refresh it
(`/regenerate-codemap`) rather than working from a guess.

If the vault is not available, say so rather than staying quiet about it, then orient from the
repo itself. Start with the fitter contract comment at the top of `R/fitters.R` — it explains
more of this package's design than any other file.

## Reading the SAS side

Several rules here only make sense against the macro they port. The macros live in
`~/Documents/macro.library` (`bootstrap.models.sas`, `bootstrap.summary.sas`,
`bootstrap.clusters.sas`). If a question is "does this match SAS", read the macro rather than
reasoning from the R — and remember the parity scope: `boot_summary()` is exact, resampling
and fitting are not.

## Prose

`AGENTS.md` points at the house voice. In Claude Code, apply the `ehrlinger-writing` skill:
it carries the same voice, reader persona and project context, kept in sync from the vault
sources. For documentation *structure*, the `r-package-style` skill is the companion.
