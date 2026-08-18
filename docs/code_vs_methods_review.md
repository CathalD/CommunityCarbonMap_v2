# Code vs. Methods — alignment and defensibility review

Merges three things into one list, ordered so it can be worked through in the
order the workflow runs:

1. the original code-vs-Methods alignment review (findings `A`–`E`);
2. the bugs that only surfaced running against Fort Severn rather than the toy
   AOI (findings `N`);
3. the defensibility critique — what a reviewer will attack (findings `R`).

Status: **DONE** fixed and verified · **PART** partly addressed · **OPEN** not
started · **DECIDE** blocked on a decision from you.

Findings marked *[verified]* were confirmed by running the code; *[read-only]*
means it was read but not executed.

---

## The one-paragraph version

The posterior **mean** is not where the argument will be. It is defensible. The
argument is about the posterior **uncertainty**, and there are exactly three
ways it is currently overconfident: the prior and the evidence are treated as
independent when they are not (`R1`), the AOI prior variance ignores spatial
correlation between pixels (`R4`), and a cross-validated RMSE is being used as
a per-pixel variance (`R3` = `A2`). Each has a concrete, publishable fix. Fixing
all three moves this from "a weighted average of two maps" to something much
closer to hierarchical spatial data fusion, and shifts the reviewer's question
from *"is this valid?"* to *"how well are the covariances estimated?"* — which
is the argument you want to be having.

Separately and more urgently: `A6`, the prior and the observations are not
measuring the same quantity, and `N8` is blocking the pipeline.

---

## Step 0 — ingest and inventory

| # | Finding | Status |
|---|---|---|
| N1 | `sf_as_ee()` on an `sfc` already returns an `ee$Geometry`; calling `$geometry()` raised `AttributeError` | **DONE** `14c64f5` |
| N3 | Covariate table timed out — reducing 10 m NDVI/land cover at native scale is ~56 M px per layer × 3 calls | **DONE** `0e956ef` — one 250 m `summary_scale` |
| N9 | `slope.tif` unreadable (`TIFFReadEncodedTile failed`) — Drive transfer reset, truncated file left in place | Worked around locally via `terra::terrain()`; **not codified** |
| N10 | Ingest dropped partial-coverage cores, pre-empting step 2 | **DONE** `11b6ff5` — all 8 cores, all 22 layers |
| D2 | Filenames hardcode `_10m` regardless of resolution | **OPEN** *[verified]* — `prior_mean_10m.tif` contains a **30 m** raster |

---

## Step 1 — characterize the prior  ← **the biggest defensibility gap**

| # | Finding | Status |
|---|---|---|
| E1 | Code separates the AOI mean from the typical pixel SD and refuses to conflate them — **better than the Methods text** | Adopt into the text |
| D1 | Returns two scalars; the masked rasters are built then discarded, though the Methods promises pixel-level detail | **OPEN** |
| B5 | One `prior_mean` / one `prior_sd`; nothing loops over depth intervals | **PART** |
| **R4** | **AOI prior variance ignores spatial correlation** | **OPEN — highest-value fix** |
| **R2** | Reducing a map to one number discards spatial structure | **OPEN** — see step 10 |

**R4 in detail.** Averaging the per-pixel SD raster gives the typical uncertainty
of *one pixel*. The code already says so and refuses to call it the uncertainty
of the AOI mean — good. But nothing yet computes the quantity that *is* needed:

```
naive (pixels independent, too optimistic):
    Var(mu_p) = (1/n^2) * sum_i sigma_i^2

correct:
    Var(mu_p) = (1/n^2) * ( sum_i sigma_i^2 + 2 * sum_{i<j} Cov(X_i, X_j) )
```

The practical route avoids the full covariance matrix. Fit a variogram to the
prior surface, extract the correlation `rho`, and use an effective sample size:

```
n_eff = n / (1 + (n - 1) * rho)
Var(mean) ~= mean(sigma^2) / n_eff
```

With 40 million strongly autocorrelated pixels, `n_eff` may be in the hundreds.
That is the difference between an AOI uncertainty that is absurdly small and one
a reviewer will accept. `gstat` is already a dependency, so this is a contained
addition to `characterize_prior()` — and it is the single change that most
strengthens the paper.

---

## Step 2 — harmonize depths

| # | Finding | Status |
|---|---|---|
| N4 | `depthharm()` failed ("differing number of rows: 8, 22"); splining a concentration also does not conserve mass | **DONE** `d6ba76c` — overlap weighting in base R, reproduces sheet 4 exactly *[verified]* |
| B5 | Multi-depth support | **PART** — now 0–15 / 15–30 / 30–50 / 50–100 plus exponential extrapolation to 100 cm. The raster side is still single-depth |

---

## Steps 3–4 — extract covariates, prior vs. observed

| # | Finding | Status |
|---|---|---|
| N2 | `[crop] extents do not overlap` — AOI in degrees, rasters in projected metres; `crop()` does not reproject | **DONE** `dbc67cc` |
| N5 | `bias`/`mae`/`rmse` all `NA` — the peat prior is NoData over mineral ground | **DONE** `2aba93e` — counted and reported, not hidden with `na.rm` |
| **A6** | **Prior and observations are on different depth bases** | **OPEN — largest open item** |

**A6, measured rather than suspected:**

```
observed (0-30 cm cores)   mean  8.63 kg C/m2
prior at the plots               44-48 kg C/m2
bias = -36.78    mae = 36.78    rmse = 37.62
z_residual = -1.2 to -1.9 at EVERY plot, same sign
```

MAE equals |bias| to two decimals — the error is almost pure offset, not scatter.
A Normal–Normal update cannot see a systematic offset as anything but evidence to
be averaged, so it will pull the ground data toward a prior measuring a different
quantity, and the posterior will be **precise and wrong** wherever the prior
dominates. Converting the prior by peat thickness (30 / 184 cm) gives ≈10.5
kg C/m² against the cores' 8.63 — within 22%, versus 4–5× raw.

This is also `R6`: *support must match the question, not the raster resolution.*
Decide the estimand first — regional mean, or pixel value — and make both the
prior and the field data estimate that same thing.

---

## Step 5 — spatial residuals

| # | Finding | Status |
|---|---|---|
| D5 | Moran's I existed but defaulted off, and nothing consumed the result | **PART** — now guarded by n (skips below 5 residuals; variogram below 15), `k = floor((n-1)/3)`. Still nothing downstream acts on it |
| B1 | Kriging / IDW / strata extrapolation — three named in the Methods, none implemented | **DECIDE** |
| **R2** | Residual interpolation is the defense against "you destroyed the spatial structure" | **OPEN** |

**R2 in detail.** This is the answer to *"you reduced a map to one number"*, and it
is the same work as `B1`:

```
r_i = observed_i - predicted_i          # residuals at plots
R(x,y) = interpolate(r_i)               # kriging / IDW / GP / spline
Posterior(x,y) = Prior(x,y) + R(x,y)
```

Original gradients retained, local bias corrected. **The cost is that it requires
the residuals to be spatially autocorrelated** — if they are random, the
correction surface is noise. Your current evidence: Moran's I = 0.277, p = 0.034,
but on 7 points with k = 2. Suggestive, not conclusive; I would not commit a
spatial model on it.

Note this also resolves `C1` (the ordering question): residual interpolation *is*
"model the ground data spatially, then adjust the prior", which is the order your
Methods describes.

---

## Steps 6–8 — build, validate, compare

| # | Finding | Status |
|---|---|---|
| A1 | `prior` was an RF predictor *and* the prior in the update — counted twice | **DONE** `47cd9f2` |
| N6 | "argument is of length zero", every fold — parsnip treats explicit `mtry = NULL` as *supplied* → `min_cols(NULL, x)` | **DONE** `a36bc71` — **latent, would fail at any n** |
| D5 | `v = 5` on 8 plots left 1–2 per fold | **PART** — `v` capped, `rsq` dropped when unestimable |
| E3 | Step 8's "stop if the RF does not beat the prior" gate | Good practice — add to the text |
| **R1** | **Prior and evidence are not independent even now** | **OPEN** |

**R1 in detail.** `A1` fixed the egregious case. The deeper objection survives:
even with field plots excluded from training, both the prior and the evidence
depend on climate, terrain, soils and landscape context, so `Cov(mu_p, mu_e) > 0`.
The standard update assumes it is zero and is therefore overconfident.

Mitigations you already have: field plots were not in the training data, and the
`prior` band is no longer a predictor. What is missing is quantifying the
residual dependence. The covariance-adjusted update, with `c = rho * sigma_p * sigma_e`:

```
mu_post  = ((sigma_e^2 - c) * mu_p + (sigma_p^2 - c) * mu_e) / (sigma_p^2 + sigma_e^2 - 2c)
Var_post = (sigma_p^2 * sigma_e^2 - c^2) / (sigma_p^2 + sigma_e^2 - 2c)
```

You cannot estimate `rho` reliably from 8 plots — so **run it as a sensitivity
analysis** at `rho = 0, 0.25, 0.5, 0.75` and report how the posterior moves. That
is cheap, honest, and much harder to attack than asserting independence. It is a
small extension to `bayesian_update_normal()`, which already reduces to the
current behaviour at `rho = 0`.

---

## Step 8b — bridge: model → rasters

| # | Finding | Status |
|---|---|---|
| N8 | `tar_make()` subprocess killed — `as.data.frame()` on 40 M cells × 6 cols | **OPEN — currently blocking.** Fix: `terra::predict()`, which blocks internally |
| **A2 / R3** | **Every pixel is assigned the same `regional_sd`, taken from the CV RMSE** | **OPEN** |
| A1 | `run_08b` may still pass `prior` in the covariate stack | **Check** |

**A2 = R3, and they are the same objection.** RMSE is average model error across
the map; it is not `Var(X_i)` for any individual pixel. Two consequences:

- the posterior SD is **insensitive to sample size** — collecting 10 more cores
  does not tighten it, which contradicts the Introduction's promise to determine
  how many samples are needed;
- uncertainty does not grow away from the data, so the map claims equal
  confidence everywhere.

Options, cheapest first:
- `ranger` with `keep.inbag = TRUE`, then `predict(type = "se")` — per-pixel SE
  in **feature** space. Already a dependency.
- kriging variance from `gstat` — per-pixel variance in **geographic** space,
  which grows with distance from samples. Already a dependency. This is what you
  described wanting in A3.
- `CAST::aoa()` — flags where the model is extrapolating. New dependency.

`A3` (weight by prior precision, ground uncertainty, sample variance, and n) is
the same work: with a spatially varying evidence SD, `sigma_e^2 = s^2 / m` falls
out naturally and the `1/sqrt(n)` behaviour appears.

---

## Steps 9–10 — the Bayesian update

| # | Finding | Status |
|---|---|---|
| N7 | Posterior had holes wherever the prior was NoData (`1/NA^2` propagates) | **DONE** `3ad85a5` — zero precision, so the posterior is the evidence there *[verified]* |
| A4 / **R5** | Normality never declared | **PART** — the four assumptions are in README §6, still absent from your Methods |
| **R1** | Covariance-adjusted update | **OPEN** — see steps 6–8 |
| **R2** | `Posterior = Prior + R(x,y)` | **OPEN** — see step 5 |

**R5.** The defense is sound and worth stating explicitly: the estimand is an AOI
*mean*, and by the CLT a mean tends to normal even when the underlying variable
is skewed — which soil carbon certainly is. Back it with a diagnostic comparing
normal / log-normal / gamma; the posterior means will likely be close, and having
checked is what matters.

---

## Steps 11–13 — export, change of support, compare

| # | Finding | Status |
|---|---|---|
| E2 | `check_change_of_support()` — you asked whether this was implemented. **It is** | *[verified]* |
| A5 | CV divides by `posterior_mean` with no guard | **OPEN** — `Inf` at mean 0, and a **negative mean silently passes** the threshold |
| B2 | Green / yellow / red categories | **OPEN** — and "25%" is still ambiguous: relative (`CV < 0.75 x threshold`) or percentage points (`CV < threshold - 0.25`)? At a 20% threshold those are 15% and −5% |
| D4 | "meaningful adjustments" has no threshold | **OPEN** — suggest `abs(delta_mu) > 1.96 * prior_sd` |
| **R6** | Support must match the question | **OPEN** — see `A6` |

---

## Steps 15–16 — precision and next samples

| # | Finding | Status |
|---|---|---|
| B6 | Precision gap should be mapped *before* sampling; currently runs at step 15 on the posterior | **OPEN** |
| B3 | Required sample size for a target precision | **OPEN** — depends on `A2` |
| B4 | Neyman allocation | **OPEN** (Methods says optional; the Intro implies more) |
| D3 | `posterior_sd + abs(z_residual)` adds kg C/m² to a unitless z-score | **OPEN** *[verified — runs silently, and resamples across mismatched grids without warning]* |

---

## New stage — calibration validation (`R7`)

Not in the Methods and not in the code, and it is the strongest single thing you
could add to the paper. Hold out AOIs, then check:

```
Z = (mu_field - mu_posterior) / sqrt(Var_field + Var_posterior)
```

If the uncertainty is honestly quantified, `Z ~ N(0,1)`. If `Z` is too wide, you
are overconfident — which is exactly what `R1`, `R3` and `R4` predict. This turns
"we propagated uncertainty" from an assertion into a testable claim, and it is
the direct empirical answer to every criticism above.

---

## Version 2 — hierarchical spatial fusion (INLA / SPDE)

Already on the roadmap: the workshop's Step 14 is *"don't implement the advanced
Bayesian model yet"*, and `README` §6 names `brms` / `INLA` / `inlabru` as
Version 2. So yes, considered — and the proposed fusion workflow is exactly what
the defensibility section above says this framework converges toward. It closes
`R1`, `R2`, `R3` and `R4` in one model rather than four patches:

| Criticism | How the SPDE model answers it |
|---|---|
| `R1` prior/evidence dependence | No "combine two independent estimates" step exists, so the assumption is never made |
| `R2` spatial structure lost | The spatial random field *is* the residual surface, estimated rather than interpolated post hoc |
| `R3` RMSE is not a variance | Posterior variance is produced per pixel, natively |
| `R4` spatial correlation in the AOI mean | The SPDE range parameter is the correlation length, estimated from data |

### The best idea in it, and it is cheap enough for Version 1

`prior_trend = df_fused$prior_pred` enters as a **fixed effect with an estimated
coefficient**. That is a bigger change than it looks: the prior stops being a
Bayesian prior and becomes a covariate. The model then *estimates* how much to
trust it. If the prior runs 4× high, the coefficient shrinks and the intercept
absorbs the offset — which means **`A6` is handled automatically** instead of
requiring a depth-basis conversion decided in advance.

**But this forces an architectural choice, and it is `C1` in a new guise.** There
are two coherent designs and you must pick one:

- **(a) Prior as prior.** Do not use it as a predictor. Combine it with
  independent evidence through the Normal–Normal update. Requires the `R1`
  covariance correction and an explicit `A6` depth-basis fix.
- **(b) Prior as covariate.** Regress the observations on it, let the data set
  the coefficient, and take the spatial field as the correction. No separate
  update step. Handles bias and dependence structurally. This is regression
  kriging, and it is what the INLA sketch does.

Doing both is precisely finding `A1`. Version 1 currently does (a).

### Why the sketch cannot run as written, today

- **Step 2 of the proposed workflow is impossible here.** It says *"fit the
  covariance model using the original ground points"* — but Table 3 returned
  **zero** profiles inside the AOI from WoSIS, CanPeat and the combined
  collection. There are no original ground points to fit a variogram to. The
  spatial range would have to come from the prior raster's own variogram (which
  is the `R4` work, reused) or from strong PC priors.
- **n = 8 does not identify a spatial range.** With 8 points the SPDE range and
  nugget are effectively set by `prior.range` / `prior.sigma`, not learned. That
  is legitimate Bayesian practice, but it must be stated as such, and the result
  is a sensitivity analysis over those priors rather than an estimate.
- **Do not feed the extrapolated depths to the likelihood.** Only 0–15 and 15–30
  are measured; 30–50 and 50–100 come from the step-2 exponential curve. Passing
  them in as observations makes the model re-learn a decay curve you imposed —
  circular, and it will look like a confident 3D result.
- **`AR1` across depth assumes equal spacing.** The intervals are 15, 15, 20 and
  50 cm. Use `rw1`/`rw2` on the interval midpoints, or model depth continuously.
- **`ee_monitoring_extract()` does not exist in rgee.** It looks like a conflation
  of `ee_monitoring()` (task polling) and `ee_extract()` (the actual extraction
  function). Step 3 in this repo already does that extraction locally with
  `terra::extract()`, so the GEE round trip is unnecessary.
- **`weight_precision = 0.5` for community data is arbitrary, and backwards.** It
  halves the precision of exactly the observations being fused in. If community
  measurement error is genuinely larger, it should come from the workbook's own
  error budget, not a hardcoded constant.
- **Change of support is named but not implemented** in the sketch. Point cores
  against 30 m pixels is a real mismatch; the SPDE framework can integrate the
  field over the pixel footprint, but that has to be written.

### Recommendation

Keep Version 1 as the workshop deliverable — the value of the workshop is that
every step is hand-checkable, and an INLA mesh is not. Then:

1. **Now, cheap:** adopt *prior as covariate with an estimated coefficient*
   (design (b)) in Version 1. It is an `lm()`, it fixes `A6` without a
   depth-basis argument, and it makes the `A1` question moot.
2. **Once `R4`'s variogram exists:** the range parameter it produces is the same
   quantity the SPDE needs, so that work is not thrown away.
3. **Once there are 30+ cores, or ground points inside the AOI:** move to INLA,
   with `R7`'s calibration check as the acceptance test.

---

## Suggested order of work

1. **`N8`** — unblock the pipeline (`terra::predict()`).
2. **`A6`** — decide the estimand and put prior and observations on the same
   depth basis. Nothing downstream means anything until this is settled.
3. **`A5`** — ten-minute guard, and it currently lets nonsense pass a management
   threshold.
4. **`R4`** — effective sample size in step 1. Highest defensibility gain per
   line of code.
5. **`A2`/`R3`** — per-pixel evidence uncertainty. Unlocks `A3`, `B3`, `B6`.
6. **`R1`** — `rho` sensitivity analysis in the update.
7. **`R2`/`B1`** — residual interpolation, once there are enough plots to justify
   it.
8. **`R7`** — calibration validation.

Items 4–8 are what turn this from a weighted average into a defensible
data-fusion method.
