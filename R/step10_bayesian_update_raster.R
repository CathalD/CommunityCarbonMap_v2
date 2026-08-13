# Step 10 -- Apply the update spatially
#
# Question: the same equations from step 9, at every pixel.
#
# Nothing new mathematically -- terra raster algebra runs the exact scalar
# Normal-Normal update across an entire grid at once. Returns a two-layer
# SpatRaster: posterior_mean, posterior_sd.

# Same treatment of a missing prior as step 9. This matters more here than in
# the scalar case: the peat prior is NoData over mineral ground and open water,
# so without it every one of those pixels would come out NA and the posterior
# map would have holes exactly where the ground data is the only information.
bayesian_update_raster <- function(prior_mean, prior_sd, regional_mean, regional_sd) {
  library(terra)

  prior_precision    <- ifel(is.na(prior_sd),    0, 1 / prior_sd^2)
  regional_precision <- ifel(is.na(regional_sd), 0, 1 / regional_sd^2)

  prior_mu    <- ifel(is.na(prior_mean),    0, prior_mean)
  regional_mu <- ifel(is.na(regional_mean), 0, regional_mean)

  posterior_precision <- prior_precision + regional_precision

  posterior_variance <- ifel(posterior_precision > 0,
                             1 / posterior_precision, NA)
  posterior_sd   <- sqrt(posterior_variance)
  posterior_mean <- ifel(
    posterior_precision > 0,
    posterior_variance *
      (prior_mu * prior_precision + regional_mu * regional_precision),
    NA
  )

  out <- c(posterior_mean, posterior_sd)
  names(out) <- c("posterior_mean", "posterior_sd")
  out
}
