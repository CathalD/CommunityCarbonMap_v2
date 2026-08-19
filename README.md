# CommunityCarbonMap_v2

A workflow for community and regional soil-carbon assessment. You bring soil
or sediment cores; the workflow harmonizes them to standard depths, compares
them against existing large-scale carbon maps, and combines the two — your
local measurements and the prior map — into an estimate (or a map) with honest
uncertainty, at a resolution and precision you choose.

Neither field cores nor national models are 100% accurate. The idea of this
framework is that *combining* the two, weighted by how much each can be
trusted, is the best available approximation of the truth — and it lets a
community get a rigorous answer from a realistic number of samples, then see
exactly where more sampling would help most.

**This README is the quick start only.** The concepts, the math, and worked
examples (by hand, then in R) live in the workshop:

- **Workshop** — every concept as plain language → math → by-hand example →
  R → where the code does it: `docs/workshop.html`
- **Model tier ladder** — which analysis your sample size supports:
  `docs/model_tier_ladder.md`
- **Methods review / to-do** — `docs/code_vs_methods_review.md`

---

## 1. Get the code into RStudio

You need [R](https://cran.r-project.org/) (≥ 4.3) and
[RStudio](https://posit.co/download/rstudio-desktop/).

**Option A — RStudio + Git (recommended, makes updates easy):**

1. RStudio → *File → New Project → Version Control → Git*
2. Repository URL: `https://github.com/CathalD/CommunityCarbonMap_v2`
3. *Create Project*. Later, get updates with the **Pull** button (Git pane),
   or `system("git pull")` in the console.

**Option B — no Git:** on the GitHub page, *Code → Download ZIP*, unzip, then
in RStudio *File → New Project → Existing Directory* and point it at the
folder.

Then install the packages (once per machine — several minutes):

```r
source("scripts/00_install_packages.R")
```

`terra`/`sf` handle rasters and spatial data, `targets` runs the pipeline,
`brms` fits the Bayesian models (it compiles code the first time you fit one —
that one-off wait is normal). Step 0 additionally needs Google Earth Engine
access via `rgee` — see §4.

## 2. Set up your data

Everything lives in `data/`. **You supply two things:**

| You supply | What it is |
|---|---|
| `data/aoi.geojson` | One polygon: your area of interest. Any GIS can export GeoJSON (WGS84 lon/lat). |
| The field workbook, exported as CSVs | Fill in `data/soil_carbon_calculation.xlsx` (Excel or Google Sheets — free), one row per core slice. Export **each sheet** as CSV back into `data/`, keeping the default export names (`… - 5. R export (layers).csv` etc.). Sheets 5–6 are the ones the code reads. |

Units are **kg C/m²** throughout — the workbook computes them for you from
bulk density, %C, and slice thickness.

**No data yet?** `source("scripts/00_setup_example.R")` installs a complete
fictional example — 16 cores and an AOI in the Hudson Bay Lowlands, the same
numbers every worked example in the workshop uses — so the whole pipeline runs
before you have any field data. (It backs up an existing `aoi.geojson` first.)

Everything else in `data/` (prior maps, NDVI, elevation) is downloaded by
step 0, and the two registry files (`prior_assets.csv`,
`covariate_assets.csv`) tell it what to fetch — add a row there to bring in
another map product; no code changes needed.

## 3. Run it

Scripts run in order; each does one job and writes its outputs to `outputs/`.

```r
source("scripts/run_00b_ingest_workbook.R")  # workbook CSVs -> analysis files
source("scripts/run_00_data_inventory.R")    # GEE: fetch priors + covariates,
                                             #   build the data inventory (slow first time)
source("scripts/run_01_characterize_prior.R")# what does the prior map say here?
source("scripts/run_02_harmonize_depths.R")  # cores -> standard depth intervals
source("scripts/run_03_extract_covariates.R")# prior + covariates at each core
source("scripts/run_04_compare_prior_observed.R") # residuals: map vs cores
source("scripts/run_05_spatial_residuals.R") # is the disagreement spatially patterned?
source("scripts/run_06_model_ladder.R")      # the analysis: pick a tier, fit, compare
```

Or, once the individual scripts have run cleanly, run the whole thing as a
pipeline that only re-computes what changed:

```r
targets::tar_make()        # run everything that is out of date
targets::tar_visnetwork()  # picture of the pipeline
targets::tar_read(tier0_result)   # read any result by name
```

**What you get** (in `outputs/`): the data inventory, the harmonized cores,
the core-vs-prior comparison, the tier recommendation for your sample size,
and the tier results — starting with `tier0_area_update.rds`, the area-wide
posterior estimate. Spatial tiers additionally produce posterior mean and
uncertainty maps.

## 4. Earth Engine (step 0 only)

Step 0 is the only part that talks to Google Earth Engine; everything after it
runs offline from the downloaded files.

```r
install.packages("rgee")
rgee::ee_install()        # once: Python backend
rgee::ee_Authenticate()   # once: browser sign-in
Sys.setenv(GEE_PROJECT = "your-cloud-project")
```

Raster downloads route through your Google Drive (an Earth Engine constraint,
not a choice) — expect a one-off consent screen and a few minutes per layer.

## 5. Layout

```
R/          one function per step -- the thing to read and test
scripts/    one runner per step   -- sources the function, runs it once
_targets.R  the same functions wired into the targets pipeline
data/       inputs (yours + downloaded; gitignored except registries)
outputs/    everything produced (gitignored)
docs/       workshop + reviews
```

## 6. Troubleshooting

**`ee_Initialize()` fails** — run `rgee::ee_install()` then
`rgee::ee_Authenticate()` once; set `GEE_PROJECT` to your own cloud project.

**"Asset not found or not readable"** — some registry assets are private to
specific GEE accounts. The tables report them as unavailable and continue;
public alternatives are noted in the registry's `note` column.

**"could not find the CSV for sheet N"** — export that sheet from the workbook
into `data/` keeping the default name (ends `- N. <sheet name>.csv`). Only
sheets 5 and 6 are required.

**`[crop] extents do not overlap`** — a raster on disk doesn't match your AOI
(often a stale file from an earlier area). Re-run
`scripts/run_00_data_inventory.R` to re-download for the current AOI.

**A raster won't read (`TIFFReadEncodedTile failed`)** — the Drive download
was interrupted and the file is truncated. Delete it and re-download; for
slope specifically:
`terra::writeRaster(terra::terrain(terra::rast("data/dem.tif"), v="slope", unit="degrees"), "data/slope.tif", overwrite=TRUE)`

**First `brms` model takes minutes / seems hung** — Stan compiles the model
before sampling. One-off per model shape; subsequent fits are fast.

**A prior's mean looks implausible** — check `coverage_frac` in
`outputs/prior_map_table.csv` first: a layer that covers 40% of your AOI is
reporting the mean of that 40%, not of your region.

**Numbers disagree with the spreadsheet** — the spreadsheet wins. The workbook
is verified cell-by-cell; if R disagrees, the code changed and needs fixing.
