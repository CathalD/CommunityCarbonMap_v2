# Step 11 -- Create the posterior map
#
# Question: what do we ship?
#
# Writes posterior_mean_10m.tif, posterior_sd_10m.tif, posterior_cv_10m.tif,
# and 95% bounds. Remember: the 10 m map contains genuine inferred
# fine-scale variation -- it is NOT a resampled version of the 250 m prior.
# The high-resolution detail comes from the regional covariates and ground
# observations, not from the coarse prior.

export_posterior_products <- function(posterior_mean, posterior_sd, outdir) {
  library(terra)
  dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

  posterior_cv <- posterior_sd / posterior_mean
  lower95 <- posterior_mean - 1.96 * posterior_sd
  upper95 <- posterior_mean + 1.96 * posterior_sd

  writeRaster(posterior_mean, file.path(outdir, "posterior_mean_10m.tif"),    overwrite = TRUE)
  writeRaster(posterior_sd,   file.path(outdir, "posterior_sd_10m.tif"),      overwrite = TRUE)
  writeRaster(posterior_cv,   file.path(outdir, "posterior_cv_10m.tif"),      overwrite = TRUE)
  writeRaster(lower95,        file.path(outdir, "posterior_lower95_10m.tif"), overwrite = TRUE)
  writeRaster(upper95,        file.path(outdir, "posterior_upper95_10m.tif"), overwrite = TRUE)

  invisible(list(mean = posterior_mean, sd = posterior_sd, cv = posterior_cv))
}
