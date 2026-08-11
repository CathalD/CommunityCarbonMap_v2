# Step 10 -- Apply the update spatially
#
# Question: the same equations from step 9, at every pixel.
#
# Nothing new mathematically -- terra raster algebra runs the exact scalar
# Normal-Normal update across an entire grid at once. Returns a two-layer
# SpatRaster: posterior_mean, posterior_sd.

bayesian_update_raster <- function(prior_mean, prior_sd, regional_mean, regional_sd) {
  library(terra)

  posterior_variance <- 1 / (1 / prior_sd^2 + 1 / regional_sd^2)
  posterior_sd        <- sqrt(posterior_variance)
  posterior_mean       <- posterior_variance *
    (prior_mean / prior_sd^2 + regional_mean / regional_sd^2)

  out <- c(posterior_mean, posterior_sd)
  names(out) <- c("posterior_mean", "posterior_sd")
  out
}
