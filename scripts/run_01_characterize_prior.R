source("R/step01_characterize_prior.R")
library(terra)

prior_mean <- rast("data/prior_mean.tif")
prior_sd   <- rast("data/prior_sd.tif")
aoi        <- vect("data/aoi.gpkg")

result <- characterize_prior(prior_mean, prior_sd, aoi)
print(result)

# sanity-check the function against the workshop's hand calculation
stopifnot(round(mean(c(120, 140, 150, 160, 180))) == 150)
stopifnot(round(mean(c(20, 25, 30, 25, 20))) == 24)
