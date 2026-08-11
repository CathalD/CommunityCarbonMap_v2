# CommunityCarbonMap_v2

Regional Map Updating Framework — take an existing large-scale spatial
product, fold in regional ground observations and high-resolution
covariates, and produce a defensible regional posterior map at 10–30 m,
with an explicit test for whether it's precise enough to manage by.

Full walkthrough (concept → pen-and-paper worked example → R code for every
step): **[docs/workshop.html](docs/workshop.html)**, also hosted at
https://claude.ai/code/artifact/e099dd7e-e5c3-44e9-bcb2-531d5ab4d753

## Quickstart

```r
source("scripts/00_install_packages.R")      # once per machine
source("scripts/00_generate_synthetic_data.R")  # tiny toy AOI + field plots, so
                                                 # everything below runs before
                                                 # real project data exists

source("scripts/run_00_data_inventory.R")
source("scripts/run_01_characterize_prior.R")
# ...through run_16_propose_sample_sites.R, in order
```

Or run the whole thing as a pipeline once individual scripts work:

```r
targets::tar_make()
targets::tar_visnetwork()  # see the dependency graph
```

Swap the files under `data/` for real project data (same filenames) and
skip `00_generate_synthetic_data.R` — nothing downstream changes.

## Layout

```
R/            one function per step — the thing to unit-test / hand-verify
scripts/      one script per step — sources the function, runs it once,
              writes one artifact under outputs/
_targets.R    the same functions, wired into a targets pipeline
data/         inputs (gitignored; regenerate with 00_generate_synthetic_data.R)
outputs/      everything the scripts/ + pipeline produce (gitignored)
docs/         the full workshop write-up
```

Every `R/stepXX_*.R` file is one function, matched to a `scripts/run_XX_*.R`
script that sources it and runs it once against real files on disk — no
step depends on being run inside `targets` to be tested. `_targets.R` wires
the identical function calls into `tar_target()`s so re-runs only redo what
actually changed. `R/bridge_predict_regional_raster.R` +
`scripts/run_08b_predict_regional_raster.R` are plumbing between steps 8 and
9–10 (turning the fitted tabular model into spatial `regional_mean` /
`regional_sd` rasters) — not one of the framework's numbered steps, but
needed to actually run it end to end.

| # | Step | Function | Script |
|---|------|----------|--------|
| 0 | What do we know? | `build_data_inventory()` | `run_00_data_inventory.R` |
| 1 | Characterize the prior over the AOI | `characterize_prior()` | `run_01_characterize_prior.R` |
| 2 | Harmonize ground data to target depths | `harmonize_core_depths()` | `run_02_harmonize_depths.R` |
| 3 | Extract prior + covariates at plots | `extract_prior_covariates()` | `run_03_extract_covariates.R` |
| 4 | Compare observed vs. prior | `compare_prior_observed()` | `run_04_compare_prior_observed.R` |
| 5 | Spatial residual diagnostics | `spatial_residual_diagnostics()` | `run_05_spatial_residuals.R` |
| 6 | Build the regional model | `build_rf_workflow()` | `run_06_build_regional_workflow.R` |
| 7 | Validate the regional model | `validate_rf_workflow()` | `run_07_validate_regional_workflow.R` |
| 8 | Prior vs. regional RF | `compare_prior_vs_model()` | `run_08_compare_prior_vs_model.R` |
| — | *(bridge: model → rasters)* | `predict_regional_raster()` | `run_08b_predict_regional_raster.R` |
| 9 | Bayesian update (scalar) | `bayesian_update_normal()` | `run_09_bayesian_update.R` |
| 10 | Bayesian update (spatial) | `bayesian_update_raster()` | `run_10_bayesian_update_raster.R` |
| 11 | Create the posterior map | `export_posterior_products()` | `run_11_export_posterior.R` |
| 12 | Change-of-support check | `check_change_of_support()` | `run_12_check_change_of_support.R` |
| 13 | Compare the maps | `compare_prior_posterior_maps()` | `run_13_compare_maps.R` |
| 14 | *(roadmap marker — no code; see the workshop)* | — | — |
| 15 | Management precision | `test_management_precision()` | `run_15_management_precision.R` |
| 16 | Propose next sample sites | `propose_next_sample_sites()` | `run_16_propose_sample_sites.R` |

## Version 1 vs. Version 2

Version 1 (this repo, as written) is deliberately simple: independent
pixels, ordinary v-fold cross-validation, a scalar Normal–Normal Bayesian
update applied pixel-by-pixel. Spatial covariance, spatially-structured
resampling (`spatialsample`), and a hierarchical spatial Bayesian model
(`brms` / `INLA` / `inlabru`) are Version 2 — worth building once Version 1
is demonstrated and validated on real data, not before. See the workshop's
Step 14 for what that looks like.
