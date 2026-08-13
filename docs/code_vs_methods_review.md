# Code vs. Methods — alignment review

Reviews every `R/step*.R` function against the Introduction and Methods draft,
section by section. Findings marked **[verified]** were confirmed by running the
function against synthetic data on 2026-08-12; **[read-only]** means the code was
read but not executed (no `tidymodels`/`rgee` in the review environment).

Severity: **A** = scientific defensibility, fix before the workshop ·
**B** = methods promises something the code does not do ·
**C** = ordering mismatch · **D** = hygiene · **E** = code is *ahead* of the text.

---

## Status — updated after the first real-data run

Legend: **DONE** fixed and verified · **PART** partly addressed · **OPEN** not started ·
**DECIDE** blocked on a decision from you.

| # | Methods says | Code does | Status |
|---|---|---|---|
| A1 | Prior and ground data are independent sources combined by weighting | `prior` was an RF **predictor** *and* the prior in the update | **DONE** `47cd9f2` — dropped from the `run_06` formula. `run_08b` still passes `prior` in the covariate stack — check when you reach it |
| A2 | "determine the number of field samples required" (Intro) | `regional_sd` = a constant CV RMSE, no `1/√n` | **OPEN** — needs pixel-level evidence uncertainty (kriging variance, or ranger `type = "se"`, or `CAST::aoa()`) |
| A3 | Weight by prior precision, ground uncertainty, sample variance, n | Weights by prior SD and evidence SD only | **OPEN** — you chose: keep prior weight by SD, give the evidence a spatially varying SD. Same work as A2 |
| A4 | — (not stated) | Normal–Normal conjugate update | **PART** — the four assumptions are written into README §6; still absent from your Methods text |
| A5 | CV = SD/mean × 100% | No guard on `mean ≤ 0` | **OPEN** — Inf at mean 0, and a negative mean still silently *passes* the threshold |
| A6 | *(not in the original review)* prior and observations on the same depth basis | Li is full-peat-column, cores are 0–30 cm | **OPEN — biggest open item.** `bias = −36.8`, MAE ≈ |bias|, so it is nearly pure offset. See below |
| B1 | Kriging, IDW, or strata extrapolation | None of the three exist | **DECIDE** — Moran's I = 0.277, p = 0.034, but on 7 points with k = 2. Suggestive, not conclusive |
| B2 | Green / yellow / red CV categories | Continuous CV raster + binary pass/fail | **OPEN** — and the "25%" wording still needs pinning down (relative vs percentage points) |
| B3 | Sample size needed for target precision | — | **OPEN** — depends on A2 |
| B4 | Neyman allocation (optional) | — | **OPEN** (consistent with "optional") |
| B5 | "across available depth intervals" | Single-layer rasters throughout | **PART** — step 2 now harmonizes to 0–15/15–30/30–50/50–100 and extrapolates to 100 cm. The raster side is still single-depth |
| B6 | Precision gap "quantified and mapped" before sampling | Runs at step 15, on the posterior | **OPEN** |
| C1 | ground data → spatial model → update prior → RF downscale | RF → update prior with RF output | **DECIDE** — unchanged; the ordering question is still live |
| D1 | "summarized … while retaining pixel-level spatial detail" | `characterize_prior()` returns 2 scalars | **OPEN** |
| D2 | "user-defined spatial resolutions" | Filenames hardcode `_10m` | **OPEN** — confirmed on real data: `prior_mean_10m.tif` holds a **30 m** raster |
| D3 | Rank sites by likely improvement | `posterior_sd + abs(z_residual)` | **OPEN** — adds kg C/m² to a unitless z-score |
| D4 | "meaningful adjustments" | `delta_mu` raster, no threshold | **OPEN** |
| D5 | — | No sample-size warning, no normality check, Moran's I off by default | **PART** — step 5 now guards Moran/variogram by n, step 7 caps `v`. Still no normality check, and nothing downstream consumes Moran's result |
| E1 | (text conflates them) | Step 1 separates AOI mean from typical pixel SD | **Code is better — still needs adopting into the text** |
| E2 | "resampling outputs back to prior support" | `check_change_of_support()` | **Already implemented** |
| E3 | — | Step 8 gate: stop if RF does not beat the prior | **Good practice — still add to the text** |

## Bugs found by running it on real data

None of these were in the original review; all surfaced between the toy AOI and Fort Severn.

| # | Symptom | Cause | Status |
|---|---|---|---|
| N1 | `AttributeError: 'Geometry' object has no attribute 'geometry'` | `sf_as_ee()` on an `sfc` already returns a Geometry | **DONE** `14c64f5` |
| N2 | `[crop] extents do not overlap` | AOI in degrees, rasters in projected metres; `crop()` does not reproject | **DONE** `dbc67cc` |
| N3 | Covariate table timed out | Reducing 10 m NDVI/land cover at native scale = ~56 M px/layer × 3 calls | **DONE** `0e956ef` — one 250 m `summary_scale` |
| N4 | `depthharm()`: "arguments imply differing number of rows: 8, 22" | Black box, and splining a concentration does not conserve mass | **DONE** `d6ba76c` — overlap weighting in base R, reproduces sheet 4 exactly |
| N5 | `bias`/`mae`/`rmse` all `NA`; Moran's I crashed | Peat prior is NoData over mineral ground, so plots extract `prior = NA` | **DONE** `2aba93e` — counted and reported, not hidden |
| N6 | "argument is of length zero", every fold, "All models failed" | parsnip treats an explicit `mtry = NULL` as *supplied* → `min_cols(NULL, x)` | **DONE** `a36bc71` — **latent bug, would fail at any n** |
| N7 | Posterior would have holes wherever the prior is NoData | `1/NA²` propagates | **DONE** `3ad85a5` — zero precision, so posterior = evidence there |
| N8 | `tar_make()` subprocess killed at `regional_rasters_file` | `as.data.frame()` on 40 M cells × 6 cols | **OPEN — currently blocking.** Fix is `terra::predict()`, which blocks internally |
| N9 | `slope.tif` unreadable (`TIFFReadEncodedTile failed`) | Drive download reset mid-transfer, left a truncated file | Worked around locally (`terra::terrain()` from `dem.tif`); not codified |
| N10 | Ingest dropped partial-coverage cores | Filtering at read time pre-empted step 2 | **DONE** `11b6ff5` — all 8 cores, all 22 layers |

## A6 — the depth-basis mismatch, quantified

The single most consequential open item, and it is now measured rather than suspected:

```
observed (0–30 cm cores)      mean  8.63 kg C/m²
prior at the plots            44–48 kg C/m²
bias  = −36.78     mae = 36.78     rmse = 37.62
z_residual = −1.2 to −1.9 at every plot, same sign
```

MAE equals |bias| to two decimals — the error is almost pure offset, not scatter. That is
what a depth-basis mismatch looks like: a full-peat-column prior against 0–30 cm
observations. A Normal–Normal update cannot see a systematic offset as anything other than
evidence to be averaged, so it will pull the ground data toward a prior that is measuring a
different quantity, and the posterior will be *precise and wrong* wherever the prior
dominates.

Converting the prior by peat thickness (30 / 184 cm) gives ≈10.5 kg C/m² against the cores'
8.63 — within 22%, versus 4–5× on the raw comparison. That conversion, or an equivalent
decision, is what makes step 9 meaningful.

---

## Section-by-section

### Overview → `step01_characterize_prior.R`

**Methods:** *"Both estimated carbon stocks (across available depth intervals) and
their associated uncertainties are assessed … summarized across the AOI while
retaining pixel-level spatial detail."*

**Code does [verified]:** crops and masks `prior_mean`/`prior_sd` to the AOI and
returns exactly two numbers — `aoi_mean_estimate` and `mean_pixel_sd_in_aoi`.
Test run returned 148.63 and 29.90 from a 20×20 synthetic grid.

- **D1** The masked rasters are built and then thrown away. If the text promises
  pixel-level detail, return the cropped rasters alongside the scalars — it is a
  two-line change and everything downstream (B6, the CV gap map) needs them.
- **B5** One `prior_mean`, one `prior_sd`. Nothing loops over depth intervals.
  Every product in the asset catalogue is published at 3–6 depths, so this is a
  real narrowing of the framework as written.
- **E1** The function's comment block is more careful than the Methods text: it
  states that the mean per-pixel SD is *not* the uncertainty of the AOI mean,
  because pixel errors are correlated. **The Methods should say this.** As
  drafted, "uncertainty metrics are summarized across the AOI" invites exactly
  the conflation the code refuses to make.

### Sample and Covariate Assessment → steps 0, 2, 3, 4

**Methods:** *"Existing ground observations within the AOI are identified and
compiled … harmonized to standardized depth intervals … Residuals between mapped
estimates and measured field values are calculated."*

**Aligned.** Step 0 compiles open ground data by AOI overlap, step 2 harmonizes,
step 3 extracts prior + covariates **[verified — works on a `SpatVector`, returns
`plot_id, observed, prior, prior_sd, ndvi, elevation, slope`]**, step 4 computes
residuals, bias, MAE, RMSE **[verified]**.

- Step 2 is the weak link *pedagogically*: `soilassessment::depthharm()` is a
  black box whose behaviour the repo comments still flag as unverified. The
  workbook (`data/soil_carbon_calculation.xlsx`, sheet 3) already does
  overlap-weighted harmonisation transparently and is verified cell-by-cell.
  **Recommend the spreadsheet as the manual step and `depthharm()` as the
  scale-up**, rather than the other way round.

### Incorporation of Ground Data → steps 5, 6, 9, 10 — **largest gap**

**Methods:** *"Ground data are spatially modelled using methods appropriate to the
quantity and distribution of available samples … Kriging … IDW … or simple
extrapolation within defined strata."*

**Code does:** none of these. Step 5 explicitly says *"Do NOT interpolate the
residuals in Version 1."* Step 6 goes straight to Random Forest.

- **B1** Three named methods, zero implemented. Either implement one (IDW is ~15
  lines with `gstat::idw()` and is the natural workshop choice), or narrow the
  Methods to say Random Forest is the Version 1 spatial model and kriging/IDW are
  alternatives for later.
- **C1** The Methods order is *ground data → spatial model → update prior → RF
  downscale*. The code order is *RF on ground data → update prior using the RF
  surface*. In the code RF fills **both** roles the Methods assigns to two
  different stages. This is the single decision that most changes the shape of
  the workshop.

**Methods:** *"The relative influence … determined through weighting based on: the
estimated precision of the prior map; the uncertainty associated with ground
observations; sample variance; and the number and distribution of available
samples."*

**Code does [verified]:** `bayesian_update_normal(prior_mean, prior_sd,
evidence_mean, evidence_sd)` — precision-weighted averaging on two SDs.
Reproduces the worked example exactly: 150 ± 30 with 170 ± 20 → **163.85 ± 16.64**.

- **A3** Of the four stated weighting inputs, only *prior precision* is present as
  named. Ground-observation uncertainty never enters the function signature.
  Sample variance is not used. Sample count is not used.
- **A2 — the serious one.** `predict_regional_raster()` sets **every pixel's**
  `regional_sd` to the model's CV RMSE. There is no `σ/√n`. The posterior SD is
  therefore *independent of how many cores were collected*. The Introduction's
  central promise — "determine the number of field samples required to achieve a
  user-defined level of accuracy" — cannot be delivered by this update as written,
  because collecting 10 more cores changes the posterior SD only through whatever
  it does to the CV RMSE, which can move in either direction.
- **A1 — the other serious one.** `scripts/run_06` fits
  `observed ~ ndvi + elevation + slope + prior`. The prior is a **predictor**.
  Steps 9–10 then combine that model's output with the prior *as if the two were
  independent sources of information*. They are not: the prior is inside the
  evidence. Precision adds (`1/σ²_post = 1/σ²_prior + 1/σ²_eff`), so the posterior
  SD comes out **too small** and the map looks more certain than it is. Options:
  drop `prior` from the RF formula, or update against the RF **residual** surface
  instead of the RF prediction.

### Spatial Modelling and Downscaling → step 6, bridge, step 11

**Methods:** *"The updated carbon estimates are then modelled at user-defined
spatial resolutions using a Random Forest algorithm."*

- **C1 (again)** "*updated* carbon estimates" places RF after the Bayesian update.
  The code puts it before.
- **D2 [verified]** Step 11 writes `posterior_mean_10m.tif`, `posterior_sd_10m.tif`,
  `posterior_cv_10m.tif` regardless of the actual resolution — my test grid was
  1 unit/pixel and still produced `_10m` filenames. Either take a `res_label`
  argument or drop the suffix.
- **[read-only]** `predict_regional_raster()` pulls the whole covariate stack into
  a data.frame with `as.data.frame(..., na.rm = FALSE)`. At 30 m over a 5 590 km²
  AOI that is ~6.2 M rows × n covariates in memory at once. Fine for the toy AOI,
  likely to fall over on the real one — worth a tiled `terra::predict()` instead.

### Validation and Uncertainty Assessment → steps 12, 13, 11, 15

**Methods:** *"resampling outputs back to the spatial support of the prior
datasets."*

- **E2 — this is implemented.** `check_change_of_support()` **[verified]**:
  `resample(posterior, prior, method = "average")`, returns the aggregated raster,
  the difference layer, and `mean_difference` (13.99 on my test data, matching
  step 13's `delta_mu` mean exactly — the two are consistent).
  One note: when the fine grid nests exactly inside the coarse one,
  `terra::aggregate(fact = …)` is the exact operation; `resample(method="average")`
  is the right general fallback but is not identical. Worth a comment.

**Methods:** *"Comparison layers are generated to identify areas of agreement and
areas where local data have resulted in meaningful adjustments."*

- Implemented as `delta_mu` and `1 - posterior_sd/prior_sd` **[verified: 13.99 and
  0.481 mean uncertainty reduction]**.
- **D4** "Meaningful" has no operational definition. Suggest
  `abs(delta_mu) > 1.96 * prior_sd` (the change exceeds the prior's own noise) so
  the comparison layer is a claim rather than a colour ramp.

**Methods:** *"Areas are categorized as Green: CV more than 25% below the
user-defined threshold; Yellow: within 25%; Red: more than 25% above."*

- **B2 — not implemented.** Step 11 writes a continuous CV raster; step 15 returns
  `cv` (a `SpatRaster` **[verified]**) and `passes` (binary). There is no
  three-way categorisation anywhere.
- The text is also ambiguous: "25% below the threshold" could mean
  `CV < 0.75 × threshold` (relative) or `CV < threshold − 0.25` (absolute
  percentage points). At a 20% threshold those are 15% and −5% — very different.
  **This needs to be pinned down before it is coded.**
- **A5 [verified]** `test_management_precision()` computes `posterior_sd /
  posterior_mean` with no guard. With `posterior_mean = 0` I got **200 infinite
  CV cells out of 400**, and `passes` contained no `NA` — the Infs simply
  evaluate `Inf < 0.20` → `FALSE`. Worse: a **negative** posterior mean gives a
  **negative** CV, and `negative < 0.20` → `TRUE`, so a nonsensical pixel
  **silently passes** the management threshold. Negative posterior means are
  reachable — step 11 already writes a `lower95` layer that can go below zero.
  Guard with `mean <= 0 → NA` before this is used to make a decision.

### Sampling Recommendations → step 16

**Methods:** *"identifying locations where additional observations are most likely
to improve confidence … Optional … Neyman allocation."*

- Implemented as a rank on posterior SD **[verified — returns the top-n cell
  coordinates]**.
- **D3 [verified]** With `z_residual` supplied, the score is
  `posterior_sd + abs(resample(z_residual, posterior_sd))` — adding a quantity in
  kg C/m² to a unitless z-score. Whichever has the larger numeric range dominates
  arbitrarily. Standardise both before summing, or weight them explicitly.
  I also passed a `z_residual` on a coarser grid and it resampled and returned
  results **with no warning** about the support mismatch.
- **B3** No function estimates *how many* samples are needed. This is promised in
  the Introduction, not just as an option.
- **B4** Neyman allocation absent — consistent with the Methods ("optional"), but
  the Introduction's phrasing implies a delivered capability. Align one to the other.

### Cross-cutting: assumptions and diagnostics

- **A4** The Normal–Normal update assumes (i) Gaussian prior and likelihood,
  (ii) independence of prior and evidence (violated — A1), (iii) known, fixed
  variances, (iv) pixel independence when applied cell-by-cell. **None of these
  four are stated in the Methods.** They belong in the text, not only in code
  comments — carbon stocks are right-skewed and often better modelled lognormally,
  which a reviewer will raise.
- **D5** No diagnostics exist. There is no minimum-sample-size warning (the
  framework is aimed at 5–20 plots, where `vfold_cv(v = 5)` leaves 1–4
  observations per fold and RMSE is extremely unstable), no residual normality
  check to justify the Gaussian update, and although `spatial_residual_diagnostics()`
  can run Moran's I, it defaults to `FALSE` and **nothing downstream consumes the
  result** — so detected autocorrelation changes nothing.

---

## Workshop-appropriateness

| Step | Manual-first? | Verdict |
|---|---|---|
| 1 characterize prior | Yes — mean of 5 pixels | Ideal |
| 2 harmonize depths | **Use the workbook, not `depthharm()`** | Spreadsheet is transparent and verified; the package is a black box |
| 4 residuals | Yes — subtraction | Ideal |
| 9 Bayesian update | Yes — verified 150±30 ⊕ 170±20 → 163.85±16.64 | **The centrepiece.** Hand-calculable in 4 lines |
| 12 change of support | Yes — average 4 pixels, compare | Good |
| 13 compare maps | Yes — one subtraction, one ratio | Ideal |
| 15 CV / precision | Yes — one division | Ideal, once A5 is guarded |
| 6–7 RF + CV | No — interpret only | `build_rf_workflow()` returns an *untrained* workflow, which is a subtle idea for beginners; say so explicitly |
| 16 sample siting | Partly | Ranking is intuitive; the composite score (D3) is not |

Complexity is well matched overall: no step reaches for machinery it does not need,
and the Version 1 / Version 2 split is stated honestly throughout. The mismatch is
not that the code is too complex — it is that the **Methods text promises more
methods than the code implements** (B1–B6), and that two statistical shortcuts
(A1, A2) undercut the framework's headline claim.
