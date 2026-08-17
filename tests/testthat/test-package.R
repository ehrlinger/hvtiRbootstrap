test_that("the package is loadable and correctly identified", {
  expect_equal(as.character(utils::packageVersion("hvtiRbootstrap")), "0.1.0")
})
