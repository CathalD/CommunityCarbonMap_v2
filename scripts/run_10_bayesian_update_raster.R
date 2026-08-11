source("R/step10_bayesian_update_raster.R")
library(terra)

prior_mean <- rast("data/prior_mean_10m.tif")
prior_sd   <- rast("data/prior_sd_10m.tif")

# regional_mean/regional_sd come from run_08b_predict_regional_raster.R --
# resample onto the prior's exact grid so the raster algebra below has
# matching geometry to work with.
regional_mean <- resample(rast("outputs/regional_mean_10m.tif"), prior_mean, method = "bilinear")
regional_sd   <- resample(rast("outputs/regional_sd_10m.tif"),   prior_mean, method = "bilinear")

posterior <- bayesian_update_raster(prior_mean, prior_sd, regional_mean, regional_sd)
writeRaster(posterior, "outputs/posterior_10m.tif", overwrite = TRUE)
