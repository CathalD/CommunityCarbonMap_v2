# Step 1 -- Characterize the prior over the AOI
#
# Question: what does the existing map tell us about our region?
#
# Reports two DIFFERENT numbers and never conflates them:
#   - aoi_mean_estimate:    the AOI-wide mean of the prior estimate raster
#   - mean_pixel_sd_in_aoi: the average PER-PIXEL uncertainty within the AOI
#
# The second is NOT the uncertainty of the AOI-wide mean -- nearby pixels
# have correlated errors, so treating pixels as independent understates the
# true uncertainty of the mean. Version 1 reports the two numbers separately
# and labels them honestly instead of pretending to solve that problem here.

characterize_prior <- function(prior_mean, prior_sd, aoi) {
  library(terra)

  # crop() does not reproject -- a CRS mismatch surfaces as the confusing
  # "[crop] extents do not overlap". The AOI is supplied in degrees while the
  # downloaded rasters are in projected metres, so align it first.
  if (!same.crs(aoi, prior_mean)) aoi <- project(aoi, crs(prior_mean))

  pm <- mask(crop(prior_mean, aoi), aoi)
  ps <- mask(crop(prior_sd, aoi), aoi)

  list(
    aoi_mean_estimate    = as.numeric(global(pm, "mean", na.rm = TRUE)),
    mean_pixel_sd_in_aoi = as.numeric(global(ps, "mean", na.rm = TRUE))
  )
}
