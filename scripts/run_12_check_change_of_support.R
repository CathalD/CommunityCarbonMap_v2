source("R/step12_check_change_of_support.R")
library(terra)

posterior_mean <- rast("outputs/posterior/posterior_mean_10m.tif")
prior_mean_250 <- rast("data/prior_mean.tif")

support_check <- check_change_of_support(posterior_mean, prior_mean_250)
print(support_check$mean_difference)
writeRaster(support_check$difference, "outputs/posterior_minus_prior_250m.tif", overwrite = TRUE)
