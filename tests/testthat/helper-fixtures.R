# A fixed replicate table with hand-computable answers. Synthetic: no cohort
# data enters this package.
#
#        x1   x2   x3
#   r1  1.0  2.0   NA
#   r2  2.0   NA   NA
#   r3  3.0  4.0   NA
#   r4  4.0   NA   NA
#
# x1: n=4 pct=100 mean=2.5 sd=sd(1:4) min=1 max=4
# x2: n=2 pct=50  mean=3   sd=sd(c(2,4)) min=2 max=4
# x3: n=0 pct=0   mean/sd/min/max all NA
fx_replicates <- function() {
  matrix(
    c(1, 2, 3, 4,
      2, NA, 4, NA,
      NA, NA, NA, NA),
    nrow = 4,
    dimnames = list(NULL, c("x1", "x2", "x3"))
  )
}
