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
  tar_target(data_inventory, build_data_inventory()),

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
    writeVector(md, "outputs/modelling_dataset.gpkg", overwrite = TRUE)
    "outputs/modelling_dataset.gpkg"
  }, format = "file"),

  # ---- step 4 ---------------------------------------------------------------
  tar_target(prior_comparison, compare_prior_observed(
    as.data.frame(terra::vect(modelling_data_file))
  )),

  # ---- steps 6-7 -------------------------------------------------------------
  tar_target(rf_workflow, build_rf_workflow(
    observed ~ ndvi + elevation + slope + prior, prior_comparison$field
  )),
  tar_target(rf_cv, validate_rf_workflow(rf_workflow, prior_comparison$field)),

  # ---- step 8 ------------------------------------------------------------------
  tar_target(model_comparison, compare_prior_vs_model(
    prior_comparison[c("bias", "mae", "rmse")], metrics_to_list(rf_cv)
  )),

  # ---- bridge: fitted model -> regional_mean/regional_sd rasters ------------
  tar_target(regional_rasters_file, {
    library(terra)
    ndvi_r <- rast(ndvi_file)
    prior_covariate <- resample(rast(prior_mean_10m_file), ndvi_r, method = "bilinear")
    names(prior_covariate) <- "prior"
    covariate_stack <- c(
      ndvi_r,
      resample(rast(dem_file),   ndvi_r, method = "bilinear"),
      resample(rast(slope_file), ndvi_r, method = "bilinear"),
      prior_covariate
    )
    cv_rmse <- rf_cv$mean[rf_cv$.metric == "rmse"]
    regional <- predict_regional_raster(rf_workflow, prior_comparison$field, covariate_stack, cv_rmse)
    writeRaster(regional[["regional_mean"]], "outputs/regional_mean_10m.tif", overwrite = TRUE)
    writeRaster(regional[["regional_sd"]],   "outputs/regional_sd_10m.tif",   overwrite = TRUE)
    c("outputs/regional_mean_10m.tif", "outputs/regional_sd_10m.tif")
  }, format = "file"),

  # ---- steps 9-10 ----------------------------------------------------------------
  tar_target(posterior_file, {
    library(terra)
    prior_mean_r <- rast(prior_mean_10m_file)
    posterior <- bayesian_update_raster(
      prior_mean_r,
      rast(prior_sd_10m_file),
      resample(rast(regional_rasters_file[1]), prior_mean_r, method = "bilinear"),
      resample(rast(regional_rasters_file[2]), prior_mean_r, method = "bilinear")
    )
    writeRaster(posterior, "outputs/posterior_10m.tif", overwrite = TRUE)
    "outputs/posterior_10m.tif"
  }, format = "file"),

  # ---- step 11 -----------------------------------------------------------------
  tar_target(posterior_products_files, {
    library(terra)
    posterior <- rast(posterior_file)
    export_posterior_products(
      posterior[["posterior_mean"]], posterior[["posterior_sd"]], "outputs/posterior"
    )
    file.path("outputs/posterior", c(
      "posterior_mean_10m.tif", "posterior_sd_10m.tif", "posterior_cv_10m.tif",
      "posterior_lower95_10m.tif", "posterior_upper95_10m.tif"
    ))
  }, format = "file"),

  # ---- step 12 --------------------------------------------------------------------
  tar_target(support_check_files, {
    library(terra)
    result <- check_change_of_support(rast(posterior_products_files[1]), rast(prior_mean_file))
    message("Prior vs. posterior-aggregated-to-250m difference: ", round(result$mean_difference, 2))
    writeRaster(result$posterior_aggregated, "outputs/posterior_aggregated_250m.tif", overwrite = TRUE)
    writeRaster(result$difference,           "outputs/posterior_minus_prior_250m.tif", overwrite = TRUE)
    c("outputs/posterior_aggregated_250m.tif", "outputs/posterior_minus_prior_250m.tif")
  }, format = "file"),

  # ---- step 13 --------------------------------------------------------------------
  tar_target(map_change_file, {
    library(terra)
    change <- compare_prior_posterior_maps(
      rast(prior_mean_10m_file), rast(posterior_products_files[1]),
      rast(prior_sd_10m_file),   rast(posterior_products_files[2])
    )
    writeRaster(change, "outputs/prior_posterior_change.tif", overwrite = TRUE)
    "outputs/prior_posterior_change.tif"
  }, format = "file"),

  # ---- step 15 (step 14 has no code -- see the workshop) ---------------------------
  tar_target(precision_check_files, {
    library(terra)
    result <- test_management_precision(
      rast(posterior_products_files[1]), rast(posterior_products_files[2]), cv_threshold = 0.20
    )
    writeRaster(result$cv,     "outputs/posterior_cv_check.tif",     overwrite = TRUE)
    writeRaster(result$passes, "outputs/posterior_meets_target.tif", overwrite = TRUE)
    c("outputs/posterior_cv_check.tif", "outputs/posterior_meets_target.tif")
  }, format = "file"),

  # ---- step 16 ------------------------------------------------------------------------
  tar_target(proposed_sample_sites, propose_next_sample_sites(
    terra::rast(posterior_products_files[2]), n = 10
  ))
)
