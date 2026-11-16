# The family API rubric (adopted 2026-11-16), implemented locally. These are
# specs each hvtiR package carries in a few lines of its own, NOT helpers
# imported from a sibling: importing one would move this tier 1 package behind
# that sibling in the release order.

# Errors a caller may catch carry the class `hvtiRbootstrap_<condition>`, so
# tryCatch() can select them without matching message text. errorCondition()
# with call = NULL prints exactly as stop(..., call. = FALSE) does.
.abort <- function(..., class) {
  stop(errorCondition(paste0(...),
                      class = paste0("hvtiRbootstrap_", class),
                      call = NULL))
}

# Renames ship as deprecations: the old argument keeps working for one
# release, warning once per session.
.deprecation_state <- new.env(parent = emptyenv())

.deprecated_arg <- function(fn, old, new) {
  key <- paste0(fn, ":", old)
  if (isTRUE(.deprecation_state[[key]])) return(invisible())
  assign(key, TRUE, envir = .deprecation_state)
  warning(warningCondition(
    paste0("`", fn, "()`: `", old, "` is deprecated; use `", new, "`. `",
           old, "` will be removed in the next release. This warning is ",
           "shown once per session."),
    class = c("hvtiRbootstrap_deprecated", "deprecatedWarning"),
    call = NULL
  ))
}

# The shared provenance record. Every field present; one that does not apply
# is NA of its stated type, so a provenance table prints a gap rather than a
# plausible value. `rng_kind` and `time` are read when the draw happens, which
# is why the record is built by the function that resamples and carried from
# there, never rebuilt later.
.hvti_provenance <- function(method, seed, rng_kind = RNGkind(),
                             time = Sys.time()) {
  pkg <- "hvtiRbootstrap"
  # RemoteSha is written by remotes, pak and devtools; a plain install has
  # none, and a version alone cannot tell two builds of it apart.
  sha <- utils::packageDescription(pkg, fields = "RemoteSha")
  if (length(sha) != 1L || is.na(sha) || !nzchar(sha)) sha <- NA_character_
  list(
    package  = pkg,
    version  = as.character(utils::packageVersion(pkg)),
    sha      = as.character(sha),
    method   = as.character(method),
    seed     = if (is.null(seed) || is.na(seed)) NA_integer_ else
      as.integer(seed),
    rng_kind = as.character(rng_kind),
    time     = as.POSIXct(time)
  )
}
