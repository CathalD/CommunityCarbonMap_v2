source("R/step11_compare_maps.R")
library(terra)

prior_mean   <- rast("data/prior_mean_10m.tif")
prior_sd     <- rast("data/prior_sd_10m.tif")
posterior    <- rast("outputs/posterior/posterior_mean_10m.tif")
posterior_sd <- rast("outputs/posterior/posterior_sd_10m.tif")

change <- compare_prior_posterior_maps(prior_mean, posterior, prior_sd, posterior_sd)
writeRaster(change, "outputs/prior_posterior_change.tif", overwrite = TRUE)

# check against the worked example: 1 - 16.6/30 ~= 44.7%
stopifnot(round((1 - 16.6 / 30) * 100, 1) == 44.7)
