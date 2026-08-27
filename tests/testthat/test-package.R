test_that("the package is loadable and correctly identified", {
  expect_true(nzchar(as.character(utils::packageVersion("hvtiRbootstrap"))))
})

test_that("DESCRIPTION's version matches the top of NEWS.md", {
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
  top  <- sub("^#\\s*hvtiRbootstrap\\s+", "",
              grep("^#\\s*hvtiRbootstrap", readLines(news, warn = FALSE),
                   value = TRUE)[1])
  expect_equal(trimws(top), desc)
})
