# Step 3 -- Extract prior and covariates
#
# Question: what did the prior predict at each ground observation, and what
# environmental conditions occurred there?
#
# Builds the modelling dataset: one row per plot, with the prior, its SD,
# and every covariate sampled at that exact point. `covariate_stack` should
# be a named SpatRaster (e.g. rast(list(ndvi = ..., elevation = ..., slope = ...)))
# so the extracted column names come out predictably.

extract_prior_covariates <- function(field, prior_mean, prior_sd, covariate_stack) {
  library(terra)

  field$prior    <- terra::extract(prior_mean, field)[, 2]
  field$prior_sd <- terra::extract(prior_sd, field)[, 2]

  cov_vals <- terra::extract(covariate_stack, field)[, -1, drop = FALSE]
  cbind(field, cov_vals)
}
