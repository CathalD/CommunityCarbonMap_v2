# data/

Everything here except this file, the two registries, the example dataset and
the workbook is gitignored — project data doesn't belong in git history.

## Tracked files

| File | What it is |
|---|---|
| `example_soil_cores.csv` | The workshop **example**: 16 fictional cores (48 slices) whose numbers match every worked example in `docs/workshop.html`. Regenerate with `scripts/00_generate_example_data.R`. |
| `example_aoi.geojson` | The example's fictional AOI (Hudson Bay Lowlands). |
| `soil_carbon_calculation.xlsx` | The field workbook, pre-filled with the example. Replace the yellow cells with your own field data; every grey cell recalculates. |
| `prior_assets.csv` | Registry of prior carbon-map assets (Earth Engine IDs, units, depth basis, how each product's uncertainty layer should be read). Add a row to bring in another product. |
| `covariate_assets.csv` | Registry of covariate assets (NDVI, elevation, slope, land cover). |
| `CarbonResources_Assets+Covariates` | The source catalogue the registries were distilled from. Reference only. |

## Files the workflow expects here (supplied or generated)

| File | Comes from | Read by |
|---|---|---|
| `aoi.geojson` | **you** (or `scripts/00_setup_example.R`) | step 0 |
| `soil_cores_raw.csv` | workbook sheet 5 via `run_00b`, or the setup script | step 2 |
| `field_plots.gpkg` | workbook sheet 6 via `run_00b`, or the setup script | step 3 |
| `aoi.gpkg` | step 0 (from `aoi.geojson`) | steps 1+ |
| `prior_mean*.tif`, `prior_sd*.tif`, `sentinel2_ndvi.tif`, `dem.tif`, `slope.tif` | step 0 (Earth Engine download) | steps 1–11 |

Units are kg C/m² throughout. If a raster on disk doesn't match your AOI
(stale download from a previous area), delete it and re-run step 0.
