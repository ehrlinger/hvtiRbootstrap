# Generates BOTH halves of the bn percentile parity fixture from one source, so
# the SAS program and the R test can never drift apart:
#
#   tests/testthat/fixtures/bn-percentile-input.csv  the replicate estimates
#   dev/sas/bn-percentile-fixture.sas                the same numbers as
#                                                    datalines, plus the
#                                                    PROC STDIZE call to run
#
# Run this from the repo root. It is a developer tool, not package code.
#
# WHY THE NUMBERS ARE WRITTEN OUT RATHER THAN DRAWN. A fixture that calls
# rnorm() on each side is not a fixture: R and SAS do not share an RNG stream,
# so the two halves would describe different data and the "parity" test would
# compare nothing. Every value below is a literal.
#
# WHY THESE COLUMNS. The parity claim is about PROC STDIZE's PCTLDEF=1, which
# is R's quantile(type = 4) and NOT the type = 7 default. The columns are
# chosen so that claim is actually exercised:
#   seq    1..100, where type 4 and type 7 differ most at the tails
#   ties   heavy duplicates, where percentile definitions disagree about
#          which order statistic to land on
#   skew   an asymmetric spread, so an error in interpolation shows up
#   const  no variation at all; every percentile must be the same value
#   n = 4  small enough to check by hand, and the shape of this package's
#          existing fx_replicates() fixture
#   n = 1  one observation, where an interpolating definition has nothing to
#          interpolate between

sets <- list(
  n100 = data.frame(
    seq   = 1:100,
    ties  = rep(c(1, 1, 2, 2, 3, 3, 4, 4, 5, 5), times = 10),
    skew  = round(exp(seq(0, 3, length.out = 100)), 3),
    const = rep(7, 100)
  ),
  n4 = data.frame(small = c(1, 2, 3, 4), pair = c(2, 4, 2, 4)),
  n1 = data.frame(single = 5)
)

# Long form: one row per (dataset, column, replicate). The R test pivots this
# back to a matrix; the SAS program reads the same values from datalines.
long <- do.call(rbind, lapply(names(sets), function(nm) {
  d <- sets[[nm]]
  do.call(rbind, lapply(names(d), function(cl) {
    data.frame(dataset = nm, column = cl, replicate = seq_len(nrow(d)),
               estimate = d[[cl]], stringsAsFactors = FALSE)
  }))
}))
write.csv(long, "tests/testthat/fixtures/bn-percentile-input.csv",
          row.names = FALSE, quote = FALSE)

# The SAS side. OUTSTAT is exported WHOLE, _TYPE_ column and all, rather than
# keeping named columns by position the way bn.mixed.ci.continuous.sas does
# (COL6..COL10). Position depends on how many percentile points were asked for,
# so reading _TYPE_ is what makes the returned file self-describing.
dl <- function(nm) {
  d <- sets[[nm]]
  rows <- apply(d, 1, function(r) paste(formatC(r, format = "f", digits = 6),
                                        collapse = " "))
  paste0(
    "data ", nm, ";\n",
    "  input ", paste(names(d), collapse = " "), ";\n",
    "  datalines;\n",
    paste(rows, collapse = "\n"), "\n;\nrun;\n"
  )
}
stdz <- function(nm) paste0(
  "proc stdize data=", nm, " outstat=stat_", nm, "\n",
  "            pctlmtd=ord_stat pctldef=1 pctlpts=2.5 16 50 84 97.5;\n",
  "run;\n",
  "data out_", nm, "; length dataset $8; set stat_", nm, ";\n",
  "  dataset = \"", nm, "\";\n",
  "run;\n"
)
# What R's type 4 says, embedded in the SAS file so whoever runs it can see at
# a glance whether SAS agreed, without shipping the CSV back first.
eye <- do.call(rbind, lapply(split(long, list(long$dataset, long$column),
                                   drop = TRUE), function(k) {
  q4 <- stats::quantile(k$estimate, c(.025, .16, .5, .84, .975), type = 4)
  data.frame(txt = sprintf(" *   %-5s %-6s n=%3d   %s", k$dataset[1],
                           k$column[1], nrow(k),
                           paste(formatC(q4, format = "f", digits = 4,
                                         width = 9), collapse = " ")),
             stringsAsFactors = FALSE)
}))

writeLines(c(
  "/* bn percentile parity fixture.",
  " *",
  " * Reproduces the percentile step every bn.* macro ends with:",
  " *   PROC STDIZE ... PCTLMTD=ORD_STAT PCTLDEF=1 PCTLPTS=2.5 16 50 84 97.5",
  " * on fixed, synthetic data. No cohort data, and no study, variable or",
  " * patient identifier appears here.",
  " *",
  " * PCTLDEF=1 is the weighted average at x_(np). The R side asserts that",
  " * stats::quantile(type = 4) reproduces it, and that the type = 7 default",
  " * does not.",
  " *",
  " * HOW TO RUN. Submit this on any machine with SAS. It writes one file,",
  " * bn-percentile-expected.csv, next to itself. Commit that file to",
  " * tests/testthat/fixtures/ and the R parity test will pick it up.",
  " * If the working directory is not writable, set %let out = <a path>.",
  " *",
  " * The `const` column has zero variance. PROC STDIZE may note that it",
  " * cannot standardise it; that is expected and does not affect the",
  " * percentiles, which are what this fixture is for.",
  " *",
  " * WHAT R SAYS, for eyeballing. Columns are P2.5, P16, P50, P84, P97.5",
  " * from stats::quantile(type = 4). SAS should match these.",
  " *",
  eye$txt,
  " */",
  "",
  "%let out = .;   /* directory for the CSV; \".\" is the working directory */",
  "",
  unlist(lapply(names(sets), dl)),
  unlist(lapply(names(sets), stdz)),
  "data expected;",
  paste0("  set ", paste(paste0("out_", names(sets)), collapse = " "), ";"),
  "run;",
  "",
  "proc print data=expected noobs; run;   /* so the log shows it too */",
  "",
  "proc export data=expected outfile=\"&out./bn-percentile-expected.csv\"",
  "            dbms=csv replace;",
  "run;"
), "dev/sas/bn-percentile-fixture.sas")

cat("wrote tests/testthat/fixtures/bn-percentile-input.csv (", nrow(long),
    " rows)\n", sep = "")
cat("wrote dev/sas/bn-percentile-fixture.sas\n")
