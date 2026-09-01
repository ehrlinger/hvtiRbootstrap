# Check that a bootstrap bag has the shape a report reads

The runner that produces a bootstrap screen is a study file, not a
templated one, so the fields a report reads are a contract between two
files that no shared function enforces. This is that function.

## Usage

``` r
boot_validate(bag)
```

## Arguments

- bag:

  A bootstrap screen: the object
  [`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
  returns, or a single unchunked run of the same shape.

## Value

`invisible(TRUE)`. Called for the error it raises otherwise.

## Details

It replaces the `contract` chunk that each bootstrap report carried, and
it differs from that chunk in the way that matters: **it checks the
shape of every field it names, not merely that the name exists.** The
chunk passed a real bag happily while `requested` was a length-2 vector
the report could not render, and the resulting defect shipped in three
releases.

Three shapes are checked, because three things can be true of a field:

- **Scalar** - `n_boot`, `seed`, `slentry`, `slstay`, `n_rows` and
  `elapsed_mins` are each one value. A length-2 `n_boot` means the pool
  was written per phase into a field that is not per phase, and every
  count downstream is then ambiguous.

- **Per phase** - `requested` and `usable` may be a vector, and on a
  multiphase screen they are: the candidate pool is *offered* to each
  phase, so `c(early = 230, late = 230)` is one pool seen twice. They
  must be numeric and carry at least one value. `integer(0)` satisfies
  "is present" and then contributes no element rather than one, which
  collapses any table built from it.

- **Any shape** - `base_params` is read whole, and `boot` must carry
  `replicates`, `summary`, `n_success` and `n_failed`. `boot` being
  present says nothing about what is inside it. `manifest` is the one
  exception: it must be a **list**, because it is indexed by name, and
  `manifest[["sha256"]]` on a named atomic vector lacking that name is
  not `NULL` but an error – `subscript out of bounds`, naming neither
  the field nor the file.

Every failure is reported at once. An author fixing a runner wants the
whole list; one at a time turns a single fix into five renders.

`dropped`, `free_sd`, `n_chunks`, `seeds` and the engine provenance
fields are **not** required. A single unchunked run legitimately carries
none of them, and
[`boot_provenance()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_provenance.md),
[`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
and
[`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md)
each say what they do in their absence.

`free_sd` is the one of those with a shape to it: absent is fine,
present means a single value. It is the standard deviation of the
*first* free base parameter, so one number is all it can be. A per-phase
value validated cleanly and then met
[`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)'s
scalar `if`, which R makes an error naming neither the field nor the
function.

## See also

[`boot_provenance()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_provenance.md),
[`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md),
[`boot_concepts()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_concepts.md)
and
[`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md),
each of which calls this first;
[`boot_shortfall()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_shortfall.md)
for the different question of whether the pool is the run that was
launched.

## Examples

``` r
bag <- list(
  n_boot = 4L, seed = 101, slentry = 0.07, slstay = 0.05,
  base_params = "base", requested = 4L, usable = 3L,
  n_rows = 500L, elapsed_mins = 120, manifest = list(sha256 = "abc123"),
  boot = list(
    replicates = data.frame(replicate = c(1L, 2L),
                            parameter = c("early.age", "early.age"),
                            estimate = c(0.5, 0.6)),
    summary = data.frame(parameter = "early.age", n = 2L, pct = 50),
    n_success = 4L, n_failed = 0L))
boot_validate(bag)

# A per-phase `requested` is valid, not a defect: the pool is offered to
# each phase, so this is one pool seen twice.
bag$requested <- c(early = 230L, late = 230L)
boot_validate(bag)

# A per-phase `n_boot` is a defect, and this is the shape that shipped.
bag$n_boot <- c(500L, 500L)
try(boot_validate(bag))
#> Error : This bootstrap screen does not have the shape a report reads. 1 problem(s):
#>   - n_boot: expected a single value, found length 2
#> Either the runner that wrote it predates these fields, or it is not the runner this report expects. Reporting over it would print blanks where the screen's criteria belong.
```
