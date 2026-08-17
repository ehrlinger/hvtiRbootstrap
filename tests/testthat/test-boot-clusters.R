test_that("n_any counts replicates with at least one member, not the sum", {
  out <- boot_clusters(fx_cluster_replicates(),
                       list(A = c("a1", "a2"), B = "b1"))
  a <- out[out$cluster == "A", ]
  # a1 appears twice and a2 twice, but they overlap in r3, so "at least one"
  # is 3 -- summing the per-variable counts would wrongly give 4.
  expect_equal(a$n_any, 3L)
  expect_equal(a$pct_any, 75)
})

test_that("a single-member cluster matches that variable's own count", {
  out <- boot_clusters(fx_cluster_replicates(),
                       list(A = c("a1", "a2"), B = "b1"))
  b <- out[out$cluster == "B", ]
  expect_equal(b$n_any, 2L)
  expect_equal(b$pct_any, 50)
})

test_that("members are reported so a reader can see what the cluster held", {
  out <- boot_clusters(fx_cluster_replicates(), list(A = c("a1", "a2")))
  expect_equal(out$members, "a1, a2")
})

test_that("a cluster naming an unknown term errors rather than silently ignoring it", {
  expect_error(
    boot_clusters(fx_cluster_replicates(), list(A = c("a1", "nope"))),
    "cluster `A` names terms not present in the replicates: nope",
    fixed = TRUE
  )
})

test_that("clusters must be a named list", {
  expect_error(
    boot_clusters(fx_cluster_replicates(), list(c("a1", "a2"))),
    "`clusters` must be a named list", fixed = TRUE
  )
})
