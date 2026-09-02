# dev/specs

Working notes and design records that are not part of the package.

`docs/specs/` holds the specs that describe what the package **is** - the
2026-08-14 design is the one that matters. `docs/plans/` holds the
implementation plans written from them. This directory holds what comes in from
outside: handoffs from meetings, and the design notes written to answer them.
A note here is promoted to `docs/specs/` if and when it becomes the record of
what the package is, rather than the record of a decision taken about it.

Incoming handoffs are **not** committed - this repository is public, and a
handoff carries institutional context that a package spec does not need. They
stay local, and the design note restates whatever bears on the design. The
`.gitignore` enforces this.

| file | what it is |
|---|---|
| `2026-09-02-bootstrap-branches-design.md` | The answer to the 2026-09-02 handoff. Confirms the split against the macro source, corrects `boot_predict_ci()`'s signature from the 2026-08-14 spec, rejects the handoff's `conf` parameter in favour of the macros' named-column coverage, and scopes three shipped defects to fix now. Approved, pending implementation plan. |

No cohort data, and no study, variable or patient identifier, in any file here.
