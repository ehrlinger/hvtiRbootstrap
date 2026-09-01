test_that("the package is loadable and correctly identified", {
  expect_true(nzchar(as.character(utils::packageVersion("hvtiRbootstrap"))))
})

# The newest *released* version named in NEWS.md. Headings carrying no version
# are skipped: work merges under a standing "(unreleased)" heading and the bump
# renames it later, so the first heading in the file is often not a version at
# all. Extracted from the test below so that case can be exercised directly.
#
# The pattern requires "# " with a space, which is both the family's settled
# level-one convention and what CommonMark actually calls a heading; "#name" is
# a paragraph, not an h1.
news_released_version <- function(lines) {
  labels <- trimws(sub("^#\\s+hvtiRbootstrap\\s*", "",
                       grep("^#\\s+hvtiRbootstrap\\b", lines, value = TRUE)))
  versioned <- labels[grepl("^[0-9]+\\.[0-9]+\\.[0-9]+$", labels)]
  if (length(versioned)) versioned[[1]] else NA_character_
}

test_that("DESCRIPTION's version matches the newest released NEWS.md heading", {
  # This replaces an assertion against a literal version string, which fired on
  # every release and only ever caught a bump that was deliberate.
  #
  # The defect actually worth catching is the two drifting apart: a version
  # bumped without a changelog entry, or an entry written under a heading that
  # was never released. Both ship, and neither is visible from either file
  # alone.
  news <- system.file("NEWS.md", package = "hvtiRbootstrap")
  if (!nzchar(news)) news <- testthat::test_path("..", "..", "NEWS.md")
  skip_if_not(file.exists(news), "NEWS.md not available")

  desc <- as.character(utils::packageVersion("hvtiRbootstrap"))
  expect_equal(news_released_version(readLines(news, warn = FALSE)), desc)
})

test_that("an unreleased heading is skipped rather than read as the version", {
  # A pull request files its entry under "(unreleased)" and leaves Version:
  # alone. Reading the first heading blindly compares "(unreleased)" against
  # DESCRIPTION, which fails every pull request between bumps.
  expect_equal(
    news_released_version(c("# hvtiRbootstrap (unreleased)",
                            "",
                            "* Something that has merged.",
                            "",
                            "# hvtiRbootstrap 0.9.2")),
    "0.9.2"
  )
  expect_equal(news_released_version("# hvtiRbootstrap 0.9.2"), "0.9.2")
  expect_true(is.na(news_released_version("# hvtiRbootstrap (unreleased)")))
})

test_that("only a level-one heading is read as a version", {
  # The family settled on level-one version headings on 2026-09-01, after
  # hvtiR and hvtiRpropensity were found at level two. This pattern already
  # rejected "##" by construction; the rejection is pinned here so a later
  # loosening of the regex is a test failure rather than a silent return of
  # the inconsistency.
  expect_equal(news_released_version("# hvtiRbootstrap 0.9.2"), "0.9.2")
  expect_true(is.na(news_released_version("## hvtiRbootstrap 0.9.2")))
  expect_true(is.na(news_released_version("### hvtiRbootstrap 0.9.2")))

  # Not a heading at all in CommonMark, which requires a space after the hash.
  expect_true(is.na(news_released_version("#hvtiRbootstrap 0.9.2")))
})
