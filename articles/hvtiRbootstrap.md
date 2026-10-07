# Getting Started with hvtiRbootstrap

## What is this package for?

`hvtiRbootstrap` is the R port of the CORR macro library’s bootstrap
macros, written for the analysts who already run them. The job is the
one `%bootreg` does: fit the same selection procedure on each of many
bootstrap replicates, record which terms survived each time, and report
how often each one appeared. A variable chosen in 95% of replicates is a
different kind of finding from one chosen in 55%, even though a single
stepwise run on the full data would have reported both the same way.

If you have run `%bootreg` and `%SUMBOOT`, the core here is the same
three steps:

| SAS macro | R function | does |
|----|----|----|
| `%bootreg` | [`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md) | resample, fit, record the terms each model kept |
| `%SUMBOOT` | [`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md) | selection frequency and coefficient spread per term |
| `%cluster` | [`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md) | how often at least one of a correlated group was kept |

`PROC=` becomes the `fitter` argument:
[`fit_logistic()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_logistic.md),
[`fit_linear()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_linear.md)
or
[`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md).

This vignette walks one small screen from start to finish, then shows
the reporting layer and the interval branch that sit alongside it.
Everything here runs on simulated data: this vignette, the package’s
examples and its tests contain no cohort data and no PHI.

``` r

library(hvtiRbootstrap)
```

## A small screen

We simulate 200 patients with a binary outcome. Two things drive the
risk: age and body surface area (`bsa`). Weight (`wt`) is built from
`bsa`, so it carries the same information as a close correlate, the way
the two do in real data. Ejection fraction (`ef`) and `noise` carry no
signal at all.

``` r

set.seed(1)
n <- 200
age <- rnorm(n, mean = 65, sd = 10)
bsa <- rnorm(n, mean = 1.9, sd = 0.2)
wt <- 40 * bsa + rnorm(n, sd = 4)
ef <- rnorm(n, mean = 55, sd = 8)
noise <- rnorm(n)
risk <- plogis(-1 + 0.06 * (age - 65) + 2 * (bsa - 1.9))
sim <- data.frame(
  dead = rbinom(n, 1, risk),
  age, bsa, wt, ef, noise
)
round(cor(sim$bsa, sim$wt), 2)
#> [1] 0.88
```

## Resample and fit

[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
is `%bootreg`. Give it the data, a formula offering the candidate terms,
and a fitter. The arguments you know carry over: `n_rep` is `RESAMPL=`,
`sle` and `sls` are `SLE=` and `SLS=` (defaults 0.1 and 0.05),
`fraction` is `FRACTION=` and `seed` is `SEED=`. The default
`fraction = 1` draws as many rows as the data has, which is what the
macro always does.

``` r

fit <- boot_select(
  sim, dead ~ age + bsa + wt + ef + noise,
  fitter = fit_logistic,
  n_rep = 50, seed = 101
)
fit
#> <boot_selection>
#>   replicates: 50 valid of 50 attempts
#>   terms:      6
#> Use boot_summary() for per-variable selection frequencies.
```

We ask for only 50 replicates so the vignette builds quickly. A real
screen uses the default of 1000, and `n_rep` counts *valid* models, as
`RESAMPL=` does: a replicate whose fit fails is drawn again and not
counted.

The result keeps one row per replicate and one column per candidate
term. A term the model did not select is `NA` in that row:

``` r

head(fit$coefficients)
#>      (Intercept)        age      bsa wt ef     noise
#> [1,]  -18.845151 0.09491189 5.938321 NA NA        NA
#> [2,]   -5.760321         NA 2.347125 NA NA 0.4155225
#> [3,]  -13.154493 0.05032449 4.598533 NA NA        NA
#> [4,]  -11.683912 0.05089188 3.757923 NA NA        NA
#> [5,]  -12.691858 0.07215356 3.491982 NA NA        NA
#> [6,]  -12.482246 0.08497846 2.998020 NA NA        NA
```

That missingness is the design, not a gap to clean up. Counting the
non-missing values down a column gives the number of replicates that
chose the term, which is how `%SUMBOOT` counts too. Fill those `NA`s
with zero and every selection frequency in the package becomes 100%.

## How often did each term survive?

[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
is `%SUMBOOT`, held to exact parity with the macro: the same replicate
table in gives the same `n`, `pct`, mean, standard deviation, minimum
and maximum out.

``` r

s <- boot_summary(fit)
s
#>      variable  n pct         mean         sd          min         max
#> 1 (Intercept) 50 100 -11.81632597 3.98078693 -20.12327672 -3.68352059
#> 2         age 44  88   0.06450568 0.01704488   0.03997851  0.10806325
#> 3         bsa 44  88   3.66911766 1.35982119   1.65745336 10.38739303
#> 4          ef 14  28   0.05556321 0.01472348   0.03794056  0.09011302
#> 5       noise  6  12   0.40319364 0.05830257   0.31074553  0.49333764
#> 6          wt  3   6  -0.01975644 0.11950685  -0.15740392  0.05753877
```

`n` is the count of replicates that selected the term and `pct` is that
count over `n_rep`. The two real effects hold up. Age survives in 88% of
replicates and `bsa` in 88%. `ef` and `noise` carry nothing by
construction, yet they still turn up in 28% and 12%. That is stepwise
keeping a useless term by chance, and a fair reminder that a non-zero
`pct` is not evidence of anything on its own.

The coefficient columns describe the replicates that *selected* the
term, not all of them. A term chosen a handful of times has a mean and
spread computed over that handful.

## What about correlated terms?

Look at `wt`. It is selected in only 6% of replicates, which reads as
unimportant. But `wt` and `bsa` measure the same thing, and once one of
them is in the model the other has little left to add. The replicates
split their votes between the pair, so each one’s individual frequency
understates how often “body size” made it into the model.

[`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)
is `%cluster`. It asks how often *at least one* member of a group was
selected:

``` r

cl <- boot_clusters(fit, list(size = c("bsa", "wt")))
cl
#>   cluster n_any pct_any members
#> 1    size    46      92 bsa, wt
```

`n_any` is not the sum of the members’ counts. A replicate that selected
both `bsa` and `wt` counts once, which is why the cluster reads 92%
rather than 94%.

## Other model families

The fitter is the only thing that changes between a logistic, linear and
Cox screen. Each pins its own entry and removal tests to the `PROC=` it
replaces:
[`fit_linear()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_linear.md)
uses partial F like `PROC REG`,
[`fit_logistic()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_logistic.md)
enters on the score test and removes on Wald like `PROC LOGISTIC`, and
[`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md)
enters on the likelihood ratio and removes on Wald. That last one is a
registered divergence from `PROC PHREG`, which enters on the score test;
R has no score test for a Cox model to call.

[`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md)
needs the `survival` package, so this chunk runs only when it is
installed:

``` r

set.seed(2)
sim$time <- rexp(n, rate = 0.1 * exp(0.05 * (sim$age - 65)))
sim$event <- rbinom(n, 1, 0.7)

cox_fit <- boot_select(
  sim, survival::Surv(time, event) ~ age + ef + noise,
  fitter = fit_cox,
  n_rep = 20, seed = 202
)
boot_summary(cox_fit)
#>   variable  n pct       mean          sd        min        max
#> 1      age 20 100 0.05373064 0.010505942 0.04056589 0.07930614
#> 2    noise 10  50 0.20097330 0.054965195 0.15739407 0.34668697
#> 3       ef  7  35 0.02178724 0.003443837 0.01790685 0.02638474
```

A Cox model has no intercept, so there is no `(Intercept)` row here.

## From a screen to a report

The reporting layer turns a finished screen into tables. It reads a
*long* “bag” rather than the wide matrix
[`boot_select()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
returns, and
[`boot_bag()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_bag.md)
is the conversion. It takes the facts the screen cannot know about
itself: which terms are the base model, how many candidates the runner
offered, and which dataset was screened.

``` r

bag <- boot_bag(
  fit,
  base_params = "(Intercept)",
  requested = 5,
  manifest = list(sha256 = "synthetic-example")
)
```

[`boot_frequencies()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_frequencies.md)
is the per-term table a report shows. It drops the base model, which is
in every replicate by construction, and adds the Monte-Carlo error each
frequency carries, roughly `sqrt(p * (1 - p) / n)`. Give it a retention
cutoff and it marks which terms clear it, and which sit close enough
that a rerun with different seeds could move them across.

``` r

boot_frequencies(bag, threshold = 50)
#>   variable  term  n pct mc_error near_threshold retained
#> 1      age   age 44  88 4.595650          FALSE     TRUE
#> 2      bsa   bsa 44  88 4.595650          FALSE     TRUE
#> 3       ef    ef 14  28 6.349803          FALSE    FALSE
#> 4    noise noise  6  12 4.595650          FALSE    FALSE
#> 5       wt    wt  3   6 3.358571          FALSE    FALSE
```

With 50 replicates the errors are several percentage points wide. That
is one more reason a real screen runs 1000.

[`boot_health()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_health.md)
asks a different question: did the screen run at all? A screen that
selected nothing, or one whose base parameter never varied across
replicates, can still produce a tidy table of numbers that mean nothing.
This check catches both.

``` r

boot_health(bag)
#>                                 check    value   ok note
#> 1              Replicates that fitted       50 TRUE <NA>
#> 2              Replicates that failed        0   NA <NA>
#> 3   Distinct candidates ever selected        5 TRUE <NA>
#> 4 SD of the first free base parameter 3.980787 TRUE <NA>
```

## Banding an estimate instead

Everything above is the *selection* branch. The replicates are a vote,
and `NA` is how a vote is cast. The package does a second job as well.

[`boot_predict_ci()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_predict_ci.md)
is the port of `%BNMNR` and `%BNPREV`. It resamples to put a band around
an estimate, so nothing is selected and there is no `NA` semantics: the
replicates are a distribution. You supply a `statistic`, a function that
takes one resampled data frame and returns a named numeric vector. Here
it is the predicted risk at three ages:

``` r

risk_at_age <- function(d, ...) {
  m <- glm(dead ~ age, family = binomial, data = d)
  p <- predict(m, newdata = data.frame(age = c(55, 65, 75)),
               type = "response")
  stats::setNames(p, c("age55", "age65", "age75"))
}

ci <- boot_predict_ci(sim, risk_at_age, n_rep = 50, seed = 7)
summary(ci)
#>   parameter   cll_p95   cll_p68    median   clu_p68   clu_p95
#> 1     age55 0.1135267 0.1339898 0.1699794 0.2138586 0.2590603
#> 2     age65 0.2026386 0.2245035 0.2511949 0.2913305 0.3280210
#> 3     age75 0.2668723 0.3061580 0.3642916 0.3996588 0.4463299
```

No argument sets a confidence level, here or anywhere in the package.
The macros hardcode the 2.5, 16, 50, 84 and 97.5 percentiles, so both
the 95% band (`cll_p95`, `clu_p95`) and the 68% band (`cll_p68`,
`clu_p68`) come back in columns named for their coverage. The
percentiles use `quantile(type = 4)`, which is SAS’s `PCTLDEF=1`. The
bands are pointwise: each quantity is summarised on its own, so a curve
drawn through `cll_p95` is not a 95% region for the curve.

## What matches SAS, and what does not

[`boot_summary()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_summary.md)
and
[`boot_clusters()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_clusters.md)
are held to exact parity with `%SUMBOOT` and `%cluster`, and the
interval arithmetic in
[`boot_predict_ci()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_predict_ci.md)
matches `PROC STDIZE PCTLDEF=1`. Resampling and model fitting are not
parity-tested and cannot be, because R and SAS draw different samples.
So compare an R screen with a SAS screen of the same data on its
conclusions, not to the decimal.

Where the port departs from a macro on purpose, the README’s divergence
register lists the departure and the function’s help page marks it as a
**Divergence**. Most are set up so the default still behaves as SAS
does. Two are not:
[`boot_predict_ci()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_predict_ci.md)
defaults to 1000 replicates where `%BNMNR` defaults to 100 (pass
`n_rep = 100` to match), and
[`fit_cox()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/fit_cox.md)
enters on the likelihood ratio because there is no score test to call.

## Where to go next

- The function help pages,
  [`?boot_select`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_select.md)
  first. Each names the macro it ports and the SAS parameter each
  argument replaces.
- The [reference
  index](https://ehrlinger.github.io/hvtiRbootstrap/reference/index.html),
  grouped by job: resample, summarise, report, pool and band.
- [`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md),
  [`boot_chunk_files()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_chunk_files.md)
  and
  [`boot_shortfall()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_shortfall.md),
  when a screen is too long to run in one go and has to be split into
  restartable chunks.
- [`boot_provenance()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_provenance.md),
  [`boot_seeds()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_seeds.md),
  [`boot_dropped()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_dropped.md)
  and
  [`boot_concepts()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_concepts.md)
  for the rest of a report: where the screen came from, the candidates
  dropped before screening, and competing forms of one variable counted
  together.
- The [README](https://github.com/ehrlinger/hvtiRbootstrap#readme) for
  the full SAS-to-R argument map and the divergence register.
