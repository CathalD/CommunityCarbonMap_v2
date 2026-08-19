# The model tier ladder (step 6)

The analysis core of the workflow. Concepts and worked examples live in
`docs/workshop.html`; this page is the engineering reference.

## The ladder

| Tier | Model | Needs (rough) | Produces |
|---|---|---|---|
| **0** | Normal–Normal update | any n ≥ 2 | one area-wide estimate ± SD |
| **1** | `observed ~ prior` (lm) | ~30 obs | calibration: is the prior biased? |
| **2** | `+ covariates` (brms) | ~60 | covariate-adjusted estimate |
| **3** | `+ gp(x, y)` (brms) | ~80 **locations** | posterior mean + SD **maps** |
| **4** | melding — prior as a noisy observation of the latent field | ~110 | maps + change-of-support handled |

Each rung is a complete deliverable, not a stepping stone. A community with a
handful of cores asking "roughly what do we have?" is best served by Tier 0 —
a GP whose hyperparameters just reproduce their priors is a worse answer, not
a fancier one.

`tier_recommendation()` (in `R/step06_tier_ladder.R`) counts parameters per
tier against your usable n at ~10 observations per parameter and reports the
ceiling. It judges Tiers 3–4 against **distinct locations** — stacking depth
intervals multiplies rows without adding places, and a GP learns from places.
On the shipped 16-core example the ceiling is Tier 0, with Tier 1 run as a
diagnostic. The decision stays human: the function recommends, you choose.

## Two architectures — pick one, never both

The prior can enter in exactly one of two ways:

- **prior-as-prior** — the model excludes `prior`; its fit is *independent
  evidence*, which the update (steps 7–8) then fuses with the prior.
- **prior-as-covariate** — `prior` is a predictor; the model estimates how far
  to trust it, and its fitted surface **is** the posterior. Steps 7–8 must be
  skipped.

Running both uses the prior twice and understates the posterior uncertainty.
`tier_model_set()` includes candidates of both kinds so LOO/WAIC can rank
them; `model_architecture()` tags each so the winner selects the downstream
path. What the comparison *cannot* do is license running a prior-as-covariate
model and then feeding it to the update — LOO scores held-out prediction and
does not penalise a double-counted prior.

## Files

| File | Contents |
|---|---|
| `R/step06_tier_ladder.R` | `tier_recommendation()`, `tier0_area_update()`, `tier1_calibration()` |
| `R/step06_fit_bayes.R` | `fit_brms_isolated()` (each brms fit in a clean `callr` child process — avoids the name collisions between brms and the spatial/tidyverse stack), `standardize_training()`/`standardize_with()`, `tier_model_set()`, `model_architecture()` |
| `R/step06_evaluate.R` | sampling diagnostics (the gate: Rhat ≤ 1.01, ESS ≥ 400, no divergences — a model failing these cannot "win" whatever its elpd), LOO/WAIC with the small-n Pareto-k caveat surfaced, exact `manual_loo()` with a mean-only baseline, `prior_evidence_correlation()` |
| `R/step06_predict_grid.R` | prediction grid (user-set `cellsize` = your map resolution), covariate attach, chunked `posterior_epred()` → mean + SD surfaces, the two-map plot |
| `scripts/run_06_model_ladder.R` | the runner: recommendation → Tier 0 → precision-target check (`TARGET_MARGIN`, `TARGET_CONFIDENCE` at the top — both yours to set) → Tier 1 → ρ diagnostic; Tiers 2–4 behind `FIT_BAYES <- TRUE` |

## Practical notes

- **Standardize a prediction grid with the saved training statistics**
  (`outputs/std_lookup.rds`), never a fresh `scale()` on the grid — that is a
  different transformation and silently produces wrong predictions.
- **Grid resolution is a statistical choice, not just a memory one.** A fine
  grid under few cores interpolates smoothly between points and *looks* more
  certain than the data supports. Start coarse; refine as n grows.
- **Use a local UTM CRS for anything spatial.** Web Mercator (EPSG:3857)
  distorts distance badly at high latitude, which corrupts GP length scales.
- **Tier 4 is documented, not fitted** — it needs on the order of a hundred
  observations. The cheapest route there is borrowing open data (see the
  "Data to borrow" table in `code_vs_methods_review.md`), with one rule: data
  that *trained the prior* can never also be evidence in the same update.
