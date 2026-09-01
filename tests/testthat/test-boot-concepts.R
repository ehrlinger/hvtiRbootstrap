fx_concept_map <- function() {
  data.frame(
    variable = c("age", "ln_age", "bmi"),
    concept  = c("Age", "Age", "BMI"),
    stringsAsFactors = FALSE
  )
}

test_that("boot_concepts returns one row per concept per phase", {
  out <- boot_concepts(fx_bag(), fx_concept_map(), phase = fx_phase)
  expect_s3_class(out, "data.frame")
  expect_named(out, c("phase", "concept", "n_forms", "forms", "n_any",
                      "pct_any", "best_form_pct", "spread", "n_retained",
                      "retained"))
  expect_identical(nrow(out), 3L)
})

test_that("the union is NOT a sum", {
  # Replicate 1 took BOTH forms of Age, so it counts ONCE. Two forms at 50%
  # each are anywhere between 50% and 100% of replicates depending on how
  # often the same replicate took both, and no marginal percentage records
  # that -- which is why this is computed from the replicate table.
  out <- boot_concepts(fx_bag(), fx_concept_map(), phase = fx_phase)
  age <- out[out$phase == "early" & out$concept == "Age", ]
  expect_identical(age$n_forms, 2L)
  expect_identical(age$n_any, 3L)
  expect_identical(age$pct_any, 75)
  expect_identical(age$best_form_pct, 50)
  expect_identical(age$spread, 25)
})

test_that("forms that never co-occur do sum, and the spread says so", {
  # The other end of the same rule: nothing is being double counted here, so
  # the union really is the sum and spread is the full difference.
  bag <- fx_bag()
  bag$boot$replicates <- data.frame(
    replicate = c(1L, 1L, 2L, 2L, 3L, 3L, 4L, 4L),
    parameter = c("base", "early.age", "base", "early.age",
                  "base", "early.ln_age", "base", "early.ln_age"),
    estimate  = c(1, 0.5, 1.1, 0.6, 0.9, 0.3, 1.2, 0.7),
    stringsAsFactors = FALSE
  )
  out <- boot_concepts(bag, fx_concept_map(), phase = fx_phase)
  expect_identical(out$pct_any, 100)
  expect_identical(out$best_form_pct, 50)
})

test_that("a single-form concept has a spread of zero", {
  # The two views agree when there is only one way to say the thing.
  out <- boot_concepts(fx_bag(), fx_concept_map(), phase = fx_phase)
  bmi <- out[out$concept == "BMI", ]
  expect_identical(bmi$n_forms, 1L)
  expect_identical(bmi$spread, 0)
})

test_that("phases are not pooled into one concept", {
  # A variable offered to two phases is two independent screening decisions.
  out <- boot_concepts(fx_bag(), fx_concept_map(), phase = fx_phase)
  age <- out[out$concept == "Age", ]
  expect_identical(nrow(age), 2L)
  expect_setequal(age$phase, c("early", "late"))
})

test_that("the base parameters are not a concept", {
  out <- boot_concepts(fx_bag(), fx_concept_map(), phase = fx_phase)
  expect_false("base" %in% out$concept)
  expect_false(any(grepl("base", out$forms, fixed = TRUE)))
})

test_that("a variable the map does not name is its own concept", {
  # Silently dropping it would remove a screened variable from the concept
  # view with nothing to say it had gone.
  map <- fx_concept_map()
  map <- map[map$variable != "bmi", , drop = FALSE]
  out <- boot_concepts(fx_bag(), map, phase = fx_phase)
  expect_true("bmi" %in% out$concept)
  expect_identical(out$n_forms[out$concept == "bmi"], 1L)
})

test_that("without a phase rule the concepts are not split by phase", {
  map <- data.frame(variable = c("early.age", "late.age", "early.ln_age",
                                 "early.bmi"),
                    concept = c("Age", "Age", "Age", "BMI"),
                    stringsAsFactors = FALSE)
  out <- boot_concepts(fx_bag(), map)
  expect_false("phase" %in% names(out))
  age <- out[out$concept == "Age", ]
  expect_identical(age$n_forms, 3L)
  # r1, r2, r3 took early.age or early.ln_age; r4 took late.age. All four.
  expect_identical(age$pct_any, 100)
})

test_that("a threshold marks the concepts a screen retained", {
  out <- boot_concepts(fx_bag(), fx_concept_map(), phase = fx_phase,
                       threshold = 50)
  expect_true(out$retained[out$phase == "early" & out$concept == "Age"])
  expect_false(out$retained[out$concept == "BMI"])
})

test_that("n_retained counts the forms, which is the crowding number", {
  # A phase that spent several of its slots on forms of ONE concept is
  # budget-limited by redundancy, and that is invisible in a coefficient
  # table. Both forms of early Age cleared 50%, so early Age is crowded.
  out <- boot_concepts(fx_bag(), fx_concept_map(), phase = fx_phase,
                       threshold = 50)
  expect_identical(out$n_retained[out$phase == "early" &
                                    out$concept == "Age"], 2L)
  crowded <- out[!is.na(out$n_retained) & out$n_retained > 1L, ]
  expect_identical(nrow(crowded), 1L)
  expect_identical(crowded$concept, "Age")
})

test_that("without a threshold there is no retention claim", {
  out <- boot_concepts(fx_bag(), fx_concept_map(), phase = fx_phase)
  expect_true(all(is.na(out$retained)))
  expect_true(all(is.na(out$n_retained)))
})

test_that("rows are ordered by phase, then descending union", {
  out <- boot_concepts(fx_bag(), fx_concept_map(), phase = fx_phase)
  expect_identical(out$phase, c("early", "early", "late"))
  expect_identical(out$concept, c("Age", "BMI", "Age"))
})

test_that("a screen that selected nothing yields no rows", {
  bag <- fx_bag_counts(list(), n_boot = 10L)
  out <- boot_concepts(bag, fx_concept_map())
  expect_identical(nrow(out), 0L)
})

test_that("boot_concepts refuses a map that is not one", {
  # The map is the study's own vocabulary. This function receives it and must
  # never infer one, so a malformed map is an error rather than a fallback.
  expect_error(boot_concepts(fx_bag(), list(age = "Age")), "data frame")
  bad <- data.frame(variable = "age", stringsAsFactors = FALSE)
  expect_error(boot_concepts(fx_bag(), bad), "concept")
})

test_that("boot_concepts calls boot_validate and propagates its error", {
  bag <- fx_bag()
  bag$n_rows <- integer(0)
  expect_error(boot_concepts(bag, fx_concept_map()), "n_rows")
})
