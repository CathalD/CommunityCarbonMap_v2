# Not part of the framework itself -- a helper for exercising the full
# scripts/run_*.R chain end-to-end before real project data is available.
# Everything it writes goes under data/, matching the paths the run_*.R
# scripts already expect. Swap in real rasters/vectors under the same
# filenames once they exist, and the rest of the pipeline doesn't change.

# Fills a raster with base + a linear trend across x and/or y + Gaussian
# noise. Kept as a small helper (rather than raw terra::init()/values()
# arithmetic) so the trend is easy to read and to change.
.add_trend_noise <- function(r, base, x_coef = 0, y_coef = 0, noise_sd = 1) {
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  x_norm <- (xy[, "x"] - min(xy[, "x"])) / (max(xy[, "x"]) - min(xy[, "x"]))
  y_norm <- (xy[, "y"] - min(xy[, "y"])) / (max(xy[, "y"]) - min(xy[, "y"]))
  terra::values(r) <- base + x_coef * x_norm + y_coef * y_norm +
    stats::rnorm(terra::ncell(r), 0, noise_sd)
  r
}

generate_synthetic_project <- function(out_dir = "data", seed = 42,
                                        n_field = 15, extent_m = 2000) {
  library(terra)
  set.seed(seed)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  crs_m   <- "EPSG:3857"
  aoi_ext <- ext(0, extent_m, 0, extent_m)

  aoi <- as.polygons(aoi_ext, crs = crs_m)
  writeVector(aoi, file.path(out_dir, "aoi.gpkg"), overwrite = TRUE)

  # --- prior: coarse 250 m, with a smooth spatial trend + noise -----------
  prior_250 <- .add_trend_noise(
    rast(aoi_ext, resolution = 250, crs = crs_m),
    base = 120, x_coef = 30, y_coef = 30, noise_sd = 8
  )
  names(prior_250) <- "prior_mean"

  prior_sd_250 <- .add_trend_noise(
    rast(prior_250), base = 25, noise_sd = 4
  )
  names(prior_sd_250) <- "prior_sd"

  writeRaster(prior_250,    file.path(out_dir, "prior_mean.tif"), overwrite = TRUE)
  writeRaster(prior_sd_250, file.path(out_dir, "prior_sd.tif"),   overwrite = TRUE)

  # --- prior disaggregated to 10 m, for the spatial Bayesian steps --------
  prior_mean_10m <- disagg(prior_250,    fact = 25, method = "bilinear")
  prior_sd_10m   <- disagg(prior_sd_250, fact = 25, method = "bilinear")
  writeRaster(prior_mean_10m, file.path(out_dir, "prior_mean_10m.tif"), overwrite = TRUE)
  writeRaster(prior_sd_10m,   file.path(out_dir, "prior_sd_10m.tif"),   overwrite = TRUE)

  # --- covariates -----------------------------------------------------------
  ndvi <- .add_trend_noise(
    rast(aoi_ext, resolution = 10, crs = crs_m),
    base = 0.5, y_coef = 0.3, noise_sd = 0.05
  )
  values(ndvi) <- pmin(pmax(values(ndvi), 0), 1)
  names(ndvi) <- "ndvi"

  dem <- .add_trend_noise(
    rast(aoi_ext, resolution = 30, crs = crs_m),
    base = 80, x_coef = 40, noise_sd = 5
  )
  names(dem) <- "elevation"

  slope <- terrain(dem, v = "slope", unit = "degrees")
  names(slope) <- "slope"

  writeRaster(ndvi,  file.path(out_dir, "sentinel2_ndvi.tif"), overwrite = TRUE)
  writeRaster(dem,   file.path(out_dir, "dem.tif"),            overwrite = TRUE)
  writeRaster(slope, file.path(out_dir, "slope.tif"),          overwrite = TRUE)

  # --- field plots ------------------------------------------------------------
  xy <- cbind(
    x = runif(n_field, 50, extent_m - 50),
    y = runif(n_field, 50, extent_m - 50)
  )
  field <- vect(xy, type = "points", crs = crs_m)
  field$plot_id   <- seq_len(n_field)
  field$prior     <- extract(prior_mean_10m, field)[, 2]
  field$prior_sd  <- extract(prior_sd_10m,   field)[, 2]
  field$ndvi      <- extract(ndvi,  field)[, 2]
  field$elevation <- extract(dem,   field)[, 2]
  field$slope     <- extract(slope, field)[, 2]

  # simulate "observed" as the prior plus an NDVI effect plus noise, so the
  # regional RF in step 6 has something real to find.
  field$observed <- round(
    field$prior + 15 * (field$ndvi - 0.5) + rnorm(n_field, 0, 12), 1
  )

  writeVector(field, file.path(out_dir, "field_plots.gpkg"), overwrite = TRUE)
  write.csv(as.data.frame(field), file.path(out_dir, "field_plots.csv"), row.names = FALSE)

  # --- raw soil cores at mismatched depth intervals, for step 2 -----------
  depth_from <- c(0, 10, 25, 40, 70)
  depth_to   <- c(10, 25, 40, 70, 100)
  cores <- do.call(rbind, lapply(seq_len(n_field), function(i) {
    data.frame(
      plot_id      = i,
      depth_from   = depth_from,
      depth_to     = depth_to,
      soc          = round(runif(5, 8, 30), 1),
      bulk_density = round(runif(5, 1.0, 1.4), 2),
      coarse_frag  = 0
    )
  }))
  write.csv(cores, file.path(out_dir, "soil_cores_raw.csv"), row.names = FALSE)

  invisible(list(aoi = aoi, prior_mean = prior_250, prior_sd = prior_sd_250, field = field))
}
