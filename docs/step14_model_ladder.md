# Step 14 — the model tier ladder

Fills the workshop's Step 14 placeholder ("don't implement the advanced
Bayesian model yet") with an actual ladder, and **replaces the Random Forest
path** (old steps 6–8, plus the 8b bridge).

## Why the RF went

`build_rf_workflow()` fitted `observed ~ ndvi + elevation + slope` on 8 plots
with 5-fold CV, leaving 1–2 observations per assessment fold. A Random Forest
at that n memorises the training set; the cross-validated RMSE it produced was
not a measure of anything. Sun et al. (2024) make the same point for carbon
mapping — *"machine learning methods have overfitting problems, especially when
the sample plots are limited"*.

The ladder replaces it with models that are identifiable at the sample size
actually available, and says so explicitly when they are not.

## The ladder

| Tier | Model | Adds | Prior enters as |
|---|---|---|---|
| **0** | Normal–Normal update | — | **prior** |
| **1** | `observed ~ prior` | calibration for bias and scale | covariate |
| **2** | `observed ~ prior + covariates` | environmental predictors | covariate |
| **3** | `... + gp(x, y)` | spatial residual structure | covariate |
| **4** | melding: `M(B) = a(B) + b·Z(B) + δ(B)` | prior as a *noisy observation* of the latent field, at block support | second observation |

Each rung is a complete deliverable. Tier 0 is not a stepping stone to Tier 4 —
for a community with a handful of cores asking "roughly, what do we have?", it
is the right answer, and a GP whose hyperparameters only reproduce their priors
is a worse one.

## Two architectures, compared rather than assumed

The prior can enter in exactly one of two ways, and they are **mutually
exclusive**:

- **prior-as-prior** — the fitted model excludes `prior`, so it is independent
  evidence, and steps 9–10 fuse it with the prior afterwards.
- **prior-as-covariate** — `prior` is a predictor, the model estimates how far
  to trust it, and the fitted surface *is* the posterior. Steps 9–10 must not
  be run.

`tier_model_set()` contains models of both kinds so LOO/WAIC ranks them.

**What the comparison cannot settle.** LOO scores prediction of held-out cores.
Both architectures can fit the same cores equally well; where they differ is
the posterior *uncertainty*, which LOO does not penalise for a double-counted
prior. So the comparison picks the architecture — it never licenses fitting a
prior-as-covariate model *and then* feeding it to step 9. That is finding A1.

`prior_evidence_correlation()` reports ρ between prior and observations, so the
R1 sensitivity analysis starts from a measured number rather than an assumed
zero.

## Sample size for this dataset

| | |
|---|---|
| Cores | 8 |
| With a harmonized `observed` | 8 |
| With a `prior` value | 7 (the peat prior is NoData at one plot) |
| Distinct spatial locations | 8 |
| Open-data profiles inside the AOI | **0** |

At a floor of 10 observations per parameter:

| Tier | Parameters | Needed | Have | Supported |
|---|---|---|---|---|
| 0 | 0 | — | 8 | ✅ |
| 1 | 3 | 30 | 8 | ✗ (2.7/param) |
| 2 | 6 | 60 | 8 | ✗ |
| 3 | 8 | 80 | 8 | ✗ |
| 4 | 11 | 110 | 8 | ✗ |

**Recommended ceiling: Tier 0.** Tier 1 is run as a *diagnostic* (it answers
whether the prior needs rescaling, which is finding A6) but is not a fitted
predictive model at this n.

Two traps the check accounts for:

- Stacking depth intervals gives 8 × 4 = 32 rows but still **8 locations**. A GP
  learns from locations, so Tiers 3–4 are judged against location count.
- `prior` is missing at one plot, so any tier using it drops to n = 7.

## What is deferred, and what would change it

**Tier 4 is implemented in shape but not fitted.** It needs roughly 110
observations against the current 8 — a ~13× gap, not a tuning problem.

The cheapest route to raising the ceiling is borrowing data, not adding model
structure. See the "Data to borrow" table in `code_vs_methods_review.md`. The
most promising source, the Hudson & James Bay peat profiles, **trained the
prior** — so it must be run as a separate, independent comparison rather than
pooled with the community cores, or the prior ends up inside the likelihood.

## Running it

```r
source("scripts/run_14_model_ladder.R")
```

Runs the decision aid, Tier 0, Tier 1 and the ρ diagnostic. Tiers 2–4 are
behind `FIT_BAYES <- FALSE` — deliberately, since fitting them at this n
produces parameters the data cannot identify. Set it to `TRUE` to exercise the
pipeline, not to obtain a result to report.

Outputs: `tier_recommendation.csv`, `tier0_area_update.rds`,
`tier1_calibration.rds`, `prior_evidence_rho.rds`, and — when `FIT_BAYES` is on
— `tier_fits.rds`, `tier_comparison.rds`, `tier_manual_loo.rds`,
`std_lookup.rds`.

## Data-quality caveats that must not disappear

- `observed` for **PM-01-A** (cored to 14.5 cm, 48% of the target interval) and
  **PM-02-A** (20.7 cm, 69%) is **partly modelled** — step 2's exponential decay
  fills below the deepest sampled layer. `coverage_frac` and
  `extrapolated_kg_m2` travel with the modelling table so this stays visible.
- One plot has no `prior` value.
- Three FS cores carry bulk densities of 2.0–2.2 g/cm³, at or past the physical
  limit for unconsolidated soil.
- The prior and the cores are on **different depth bases** (finding A6). Tier 1's
  slope and intercept are the cheapest available correction.

## Notes for whoever runs this next

- **Grid resolution is a statistical choice.** `posterior_epred()` costs
  grid_cells × draws × training_points; a 30 m grid over this AOI is ~40 M
  cells and will kill the session. But the real reason for a coarse grid is
  that 8 cores cannot support a 30 m map — a fine grid interpolates between a
  handful of points and looks far more certain than the data warrants. Start at
  1–2 km.
- **Use UTM, not EPSG:3857.** At 56°N Web Mercator distorts distance by ~1.8×,
  so a GP length scale fitted in it is meaningless. The repo's rasters are
  currently exported in 3857.
- **Standardize a prediction grid with the saved training statistics**
  (`std_lookup.rds`), never a fresh `scale()` on the grid — a fresh call is a
  different transformation and produces wrong predictions silently.
