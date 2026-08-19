source("R/step12_management_precision.R")
library(terra)

posterior_mean <- rast("outputs/posterior/posterior_mean_10m.tif")
posterior_sd   <- rast("outputs/posterior/posterior_sd_10m.tif")

precision_check <- test_management_precision(posterior_mean, posterior_sd, cv_threshold = 0.20)
writeRaster(precision_check$cv,     "outputs/posterior_cv_check.tif",     overwrite = TRUE)
writeRaster(precision_check$passes, "outputs/posterior_meets_target.tif", overwrite = TRUE)

# scalar check against the worked example: 16.6 / 164 ~= 10.1%
stopifnot(round(16.6 / 164 * 100, 1) == 10.1)
