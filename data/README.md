# data/

Everything in this folder except this file is gitignored — real project
data doesn't belong in git history. This is the checklist of what the
scripts in `scripts/` and `_targets.R` currently expect to find here, by
filename, so real data can drop in and replace the synthetic set.

Don't have something yet, or have it in a different shape? Leave a note
below its row — steps 0–16 get reconfigured around what actually exists,
not the other way around. Nothing here is fixed.

## Reference / example data

```r
source("scripts/00_generate_synthetic_data.R")
```

generates a complete, correctly-shaped fake dataset under this folder — a
2 km toy AOI, prior rasters, covariates, and 15 field plots. Run it once to
see literal example files with the right bands/columns/CRS, or to smoke-test
the pipeline before real data exists. `R/utils_synthetic_data.R` is the
authoritative shape reference if this table and the code ever disagree.

## Expected files

| File | Type | Used by (step) | Notes |
|---|---|---|---|
| `aoi.gpkg` | vector polygon | 1 | Area of interest boundary. Any projected CRS is fine — scripts don't assume a specific one, just that it's projected (metres, not degrees) so resolution arithmetic works. |
| `prior_mean.tif` | raster, 1 band | 1, 12 | The existing large-scale product's mean estimate, at its native coarse resolution (250 m in the worked examples — **tell us the real resolution** so step 1's "typical pixel SD" language and step 12's aggregation factor get updated to match). |
| `prior_sd.tif` | raster, 1 band | 1, 13 | Per-pixel uncertainty for `prior_mean.tif`, same grid. Also: **how was this SD generated?** (Step 0's inventory asks the same question — the answer changes how much we trust it.) |
| `prior_mean_10m.tif` | raster, 1 band | 3, 6, 10, 13 | The prior at the *target* posterior resolution (10–30 m). If you only have the coarse version, we disaggregate it (`terra::disagg()`, as the synthetic generator does) rather than requiring you to produce this — say so and we'll wire that step in instead of expecting the file directly. |
| `prior_sd_10m.tif` | raster, 1 band | 3, 10, 13 | Same disaggregation question as above. |
| `sentinel2_ndvi.tif` | raster, 1 band | 3, 6 | NDVI (or your chosen vegetation index), ~10 m. Any name/index is fine as long as `R/step06_build_regional_workflow.R`'s formula (`observed ~ ndvi + elevation + slope + prior`) gets updated to match. |
| `dem.tif` | raster, 1 band | 3, 6 | Elevation, ~30 m (or whatever you have — everything gets resampled onto the NDVI grid before modelling). |
| `slope.tif` | raster, 1 band | 3, 6 | Slope in degrees. Don't have it separately? `terra::terrain(dem, v = "slope", unit = "degrees")` derives it from `dem.tif` — say so and we'll fold that into the step 3/bridge scripts instead of expecting a standalone file. |
| `field_plots.gpkg` | vector points | 3 | One row per field plot. Must carry at least `plot_id` and `observed` (the target variable — carbon stock in your project's units). Everything else (prior, covariates) gets extracted onto it by step 3, so extra columns are harmless but not required. |
| `soil_cores_raw.csv` | table | 2 | Raw depth-interval measurements feeding the depth-harmonization step. The synthetic version uses `plot_id, depth_from, depth_to, soc, bulk_density, coarse_frag`. `harmonize_core_depths()` promotes this to an `aqp::SoilProfileCollection` via `depths(df) <- plot_id ~ depth_from + depth_to` before calling `depthharm()` (confirmed by testing — `depthharm()` reaches into `soildata@horizons`, so it needs an aqp object, not a plain data.frame). Requirements this implies: `depth_from`/`depth_to` numeric, sorted, no gaps or overlaps within a `plot_id`. Still unconfirmed: whether `depthharm()` also needs the depth columns literally renamed `top`/`bottom` inside the SPC — if `run_02` still errors after the aqp fix, run `print(soilassessment::depthharm)` and send the body back. |

## What "reconfigure the steps" means in practice

Swapping in real data may mean more than dropping in files with the right
names — e.g. a different native prior resolution changes the aggregation
factor in `R/step10_check_change_of_support.R`, and a different response
variable name changes the recipe formula in
`R/step06_build_regional_workflow.R`. Once real files land here, the fastest
path is: run `scripts/run_01_characterize_prior.R` onward one at a time,
fix whichever script/function breaks on the real shape, and keep going —
the same "one function, one script" loop the workshop describes, just aimed
at real data instead of the synthetic set.

## What step 0 now generates

`scripts/run_00_data_inventory.R` is the only script that talks to Earth
Engine. It authenticates, ingests `aoi.geojson` + `community_soil_cores.csv`,
and writes the files the later steps expect, so several rows above are now
produced rather than supplied:

| Generated | By | Notes |
|---|---|---|
| `aoi.gpkg` | `write_aoi_gpkg()` | Same polygon as `aoi.geojson`, in the format `run_01` and `_targets.R` read. AOI is 5 590 km². |
| `field_plots.gpkg` | `write_field_plots()` | `plot_id` + `observed` (0–30 cm stock, kg C/m²) from the community cores. Partial-coverage cores are dropped, so this has 6 rows, not 8. |
| `prior_mean.tif`, `prior_sd.tif`, `prior_mean_10m.tif`, `prior_sd_10m.tif`, `sentinel2_ndvi.tif`, `dem.tif`, `slope.tif` | `download_aoi_stack()` | Only when `DOWNLOAD_STACK <- TRUE`. Exported clipped to the AOI at 30 m (250 m for the two coarse prior files). |

The asset lists driving it are `prior_assets.csv` (carbon maps and point
databases, the machine-readable form of `CarbonResources_Assets+Covariates`)
and `covariate_assets.csv`. Both are plain CSVs — add a row rather than edit
code to bring another product in.

`soil_cores_raw.csv` is still the one input step 2 needs that step 0 does not
produce: export sheet 5 of `soil_carbon_calculation.xlsx` to that filename.
