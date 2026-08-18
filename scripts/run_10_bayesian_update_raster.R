source("R/step10_bayesian_update_raster.R")
library(terra)

prior_mean <- rast("data/prior_mean_10m.tif")
prior_sd   <- rast("data/prior_sd_10m.tif")

# regional_mean/regional_sd used to come from run_08b (the RF bridge, now removed).
# They must now be produced by a Tier 2/3 PRIOR-AS-PRIOR model, predicted onto a
# grid with R/step14_predict_grid.R and rasterised. If the comparison instead
# favours a prior-as-covariate model, that model's posterior IS the answer and
# this step must be skipped -- running both uses the prior twice (finding A1).
# Original note:
# resample onto the prior's exact grid so the raster algebra below has
# matching geometry to work with.
regional_mean <- resample(rast("outputs/regional_mean_10m.tif"), prior_mean, method = "bilinear")
regional_sd   <- resample(rast("outputs/regional_sd_10m.tif"),   prior_mean, method = "bilinear")

posterior <- bayesian_update_raster(prior_mean, prior_sd, regional_mean, regional_sd)
writeRaster(posterior, "outputs/posterior_10m.tif", overwrite = TRUE)
