# Bridge script (see R/bridge_predict_regional_raster.R): turns the fitted
# tabular RF model into the regional_mean/regional_sd rasters that
# run_10_bayesian_update_raster.R needs. Not one of the workshop's numbered
# steps -- the plumbing between step 8 and step 9/10.

source("R/bridge_predict_regional_raster.R")
library(terra)

rf_workflow   <- readRDS("outputs/rf_workflow.rds")
training_data <- read.csv("outputs/prior_vs_observed.csv")
rf_cv         <- readRDS("outputs/rf_metrics.rds")
cv_rmse       <- rf_cv$mean[rf_cv$.metric == "rmse"]

# every predictor in the run_06 formula, on one grid, spelled exactly as
# the formula spells it (including "prior")
ndvi  <- rast("data/sentinel2_ndvi.tif")
dem   <- resample(rast("data/dem.tif"),           ndvi, method = "bilinear")
slope <- resample(rast("data/slope.tif"),         ndvi, method = "bilinear")
prior <- resample(rast("data/prior_mean_10m.tif"), ndvi, method = "bilinear")
names(prior) <- "prior"

covariate_stack <- c(ndvi, dem, slope, prior)

regional <- predict_regional_raster(rf_workflow, training_data, covariate_stack, cv_rmse)

writeRaster(regional[["regional_mean"]], "outputs/regional_mean_10m.tif", overwrite = TRUE)
writeRaster(regional[["regional_sd"]],   "outputs/regional_sd_10m.tif",   overwrite = TRUE)
