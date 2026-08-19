# The Regional Map Updating Framework as a targets pipeline.
#
# Every target below is the same function call that already lives in one
# scripts/run_XX_*.R script -- see that script first if a target here is
# unclear, or to run a single step in isolation without targets at all.
#
# terra's SpatRaster/SpatVector objects hold C++ pointers and do not survive
# ordinary RDS serialization, so any target whose result IS or CONTAINS one
# writes to outputs/ inside its command and returns the file path(s) with
# format = "file" instead of returning the object itself. Plain data.frames,
# lists of numbers, and tidymodels objects (rf_workflow, rf_cv) don't have
# this problem and use the default (rds) format.

library(targets)
tar_source("R")  # loads every step0X_*.R / bridge_*.R function
dir.create("outputs", showWarnings = FALSE)  # every writeRaster()/write.csv() below lands here

list(

  # ---- raw inputs, tracked so the pipeline reruns when they change --------
  tar_target(aoi_file,          "data/aoi.gpkg",            format = "file"),
  tar_target(prior_mean_file,   "data/prior_mean.tif",      format = "file"),
  tar_target(prior_sd_file,     "data/prior_sd.tif",        format = "file"),
  tar_target(prior_mean_10m_file, "data/prior_mean_10m.tif", format = "file"),
  tar_target(prior_sd_10m_file,   "data/prior_sd_10m.tif",   format = "file"),
  tar_target(ndvi_file,         "data/sentinel2_ndvi.tif",  format = "file"),
  tar_target(dem_file,          "data/dem.tif",              format = "file"),
  tar_target(slope_file,        "data/slope.tif",            format = "file"),
  tar_target(field_plots_file,  "data/field_plots.gpkg",     format = "file"),
  tar_target(soil_cores_file,   "data/soil_cores_raw.csv",   format = "file"),

  # ---- step 0 --------------------------------------------------------------
  # The three step-0 tables are produced by scripts/run_00_data_inventory.R,
  # which is the only part of the workflow that talks to Earth Engine. The
  # pipeline reads its CSV output instead of calling GEE itself, so tar_make()
  # never depends on an Earth Engine session being available.
  tar_target(prior_map_file,    "outputs/prior_map_table.csv",   format = "file"),
  tar_target(covariate_file,    "outputs/covariate_table.csv",   format = "file"),
  tar_target(open_ground_file,  "outputs/open_ground_table.csv", format = "file"),
  tar_target(community_cores_file, "data/community_soil_cores.csv", format = "file"),

  tar_target(data_inventory, build_data_inventory(
    priors     = utils::read.csv(prior_map_file,   stringsAsFactors = FALSE),
    covariates = utils::read.csv(covariate_file,   stringsAsFactors = FALSE),
    ground     = utils::read.csv(open_ground_file, stringsAsFactors = FALSE),
    cores      = summarize_community_cores(community_cores_file),
    aoi        = load_aoi("data/aoi.geojson")
  )),

  # ---- step 1 --------------------------------------------------------------
  tar_target(prior_summary, characterize_prior(
    terra::rast(prior_mean_file), terra::rast(prior_sd_file), terra::vect(aoi_file)
  )),

  # ---- step 2 --------------------------------------------------------------
  tar_target(harmonized_cores, harmonize_core_depths(
    read.csv(soil_cores_file)
  )),

  # ---- step 3 ---------------------------------------------------------------
  tar_target(modelling_data_file, {
    library(terra)
    field_raw <- vect(field_plots_file)[, c("plot_id", "observed")]
    ndvi_r    <- rast(ndvi_file)
    covariates <- c(
      ndvi_r,
      resample(rast(dem_file),   ndvi_r, method = "bilinear"),
      resample(rast(slope_file), ndvi_r, method = "bilinear")
    )
    md <- extract_prior_covariates(
      field_raw, rast(prior_mean_10m_file), rast(prior_sd_10m_file), covariates
    )
    # depth-harmonized 0-30 cm stock, not the workbook per-core total
    md <- attach_harmonized_observed(md, harmonized_cores)
    writeVector(md, "outputs/modelling_dataset.gpkg", overwrite = TRUE)
    "outputs/modelling_dataset.gpkg"
  }, format = "file"),

  # ---- step 4 ---------------------------------------------------------------
  tar_target(prior_comparison, compare_prior_observed(
    as.data.frame(terra::vect(modelling_data_file))
  )),

  # ---- step 6: the model tier ladder ---------------------------------------
  # Replaces the old steps 6-8 (Random Forest). An RF on a handful of plots
  # memorises them; the ladder starts at a model the data can carry and only
  # climbs when the data allows. See scripts/run_06_model_ladder.R.
  tar_target(modelling_table, {
    md <- as.data.frame(terra::vect(modelling_data_file))
    md[is.finite(md$observed), , drop = FALSE]
  }),

  tar_target(tier_ceiling, tier_recommendation(
    n = sum(is.finite(modelling_table$prior)),
    n_covariates = 3,
    n_locations = nrow(modelling_table)
  )),

  # Tier 0 is a complete deliverable, not an intermediate step.
  tar_target(tier0_result, tier0_area_update(
    modelling_table$observed,
    mean(modelling_table$prior,    na.rm = TRUE),
    mean(modelling_table$prior_sd, na.rm = TRUE)
  )),

  tar_target(tier1_result, tier1_calibration(modelling_table)),

  tar_target(prior_evidence_rho, prior_evidence_correlation(modelling_table))

  # ---- raster fusion chain (steps 7-13): PAUSED ----------------------------
  # These targets used to be fed by the RF bridge, which is gone. They need a
  # SPATIAL evidence surface -- a fitted Tier 2/3 "prior-as-prior" model turned
  # into regional_mean / regional_sd rasters via R/step06_predict_grid.R.
  #
  # At the current sample size no spatial tier is identifiable (see
  # tier_ceiling), so the chain is left unwired rather than fed a model that
  # cannot support it. Nothing is lost: R/step07-13 and their run_XX scripts
  # are unchanged and still run standalone.
  #
  # To reconnect once a spatial tier is justified: predict the fitted model
  # onto a grid, rasterise SOC_mean / SOC_sd, and pass them to
  # bayesian_update_raster() exactly as regional_mean / regional_sd were.
  #
  # NOTE: this is the prior-as-PRIOR route only. If the comparison instead
  # favours a prior-as-covariate model, its posterior IS the answer and steps
  # 7-8 must be skipped -- running both uses the prior twice (finding A1).
)
