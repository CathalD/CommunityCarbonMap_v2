# Step 0, TABLE 2 -- what covariates we have over the AOI, and the stack the
# rest of the workflow runs on.
#
# The covariate list lives in data/covariate_assets.csv. The stack this file
# builds is deliberately shaped to the filenames the EXISTING scripts already
# read, so nothing downstream has to change:
#
#   data/prior_mean.tif      run_01, run_12
#   data/prior_sd.tif        run_01, run_13
#   data/prior_mean_10m.tif  run_03, run_06, run_10, run_13
#   data/prior_sd_10m.tif    run_03, run_10, run_13
#   data/sentinel2_ndvi.tif  run_03, run_06
#   data/dem.tif             run_03, run_06
#   data/slope.tif           run_03, run_06
#
# Everything is clipped to the AOI first. Over a few thousand km2 that is the
# difference between an export that finishes and one that does not.

source_once_cov <- function(path) if (!exists("gee_init")) source(path)
source_once_cov("R/step00_gee_setup.R")

read_covariate_registry <- function(path = "data/covariate_assets.csv") {
  utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
}

# --- individual covariates --------------------------------------------------

# Sentinel-2 growing-season NDVI. SCL classes 3, 8, 9, 10, 11 are cloud shadow,
# cloud medium/high probability, cirrus and snow -- all of which matter at 56 N.
s2_ndvi <- function(aoi_ee,
                    start = "2023-06-01", end = "2023-09-15",
                    max_cloud = 40) {
  library(rgee)
  mask_clouds <- rgee::ee_utils_pyfunc(function(img) {
    scl <- img$select("SCL")
    keep <- scl$neq(3)$And(scl$neq(8))$And(scl$neq(9))$
      And(scl$neq(10))$And(scl$neq(11))
    img$updateMask(keep)
  })

  col <- ee$ImageCollection("COPERNICUS/S2_SR_HARMONIZED")$
    filterBounds(aoi_ee)$
    filterDate(start, end)$
    filter(ee$Filter$lt("CLOUDY_PIXEL_PERCENTAGE", max_cloud))$
    map(mask_clouds)

  col$median()$normalizedDifference(c("B8", "B4"))$rename("ndvi")$clip(aoi_ee)
}

# Copernicus GLO-30 is served as tiles, so it has to be mosaicked. A mosaic has
# no fixed projection, and ee$Terrain$slope() refuses to run without one --
# hence setDefaultProjection() before the terrain call.
glo30_elevation <- function(aoi_ee) {
  library(rgee)
  ee$ImageCollection("COPERNICUS/DEM/GLO30")$
    select("DEM")$
    mosaic()$
    setDefaultProjection(crs = "EPSG:4326", scale = 30)$
    rename("elevation")$
    clip(aoi_ee)
}

glo30_slope <- function(aoi_ee, dem = NULL) {
  library(rgee)
  if (is.null(dem)) dem <- glo30_elevation(aoi_ee)
  ee$Terrain$slope(dem)$rename("slope")$clip(aoi_ee)
}

worldcover <- function(aoi_ee) {
  library(rgee)
  ee$ImageCollection("ESA/WorldCover/v200")$first()$
    select("Map")$rename("landcover")$clip(aoi_ee)
}

# WorldCover class 80 is permanent water. Inverted into a land mask so the
# covariates carry the same exclusion the peat prior already has built in.
land_mask <- function(aoi_ee, lc = NULL) {
  library(rgee)
  if (is.null(lc)) lc <- worldcover(aoi_ee)
  lc$neq(80)$rename("water_mask")$clip(aoi_ee)
}

covariate_images <- function(aoi_ee, ndvi_start = "2023-06-01",
                             ndvi_end = "2023-09-15") {
  dem <- glo30_elevation(aoi_ee)
  lc  <- worldcover(aoi_ee)
  list(
    ndvi       = s2_ndvi(aoi_ee, ndvi_start, ndvi_end),
    elevation  = dem,
    slope      = glo30_slope(aoi_ee, dem),
    landcover  = lc,
    water_mask = land_mask(aoi_ee, lc)
  )
}

#' Table 2 -- covariates summarized over the AOI
# `summary_scale` is why this returns instead of timing out. NDVI and land cover
# are 10 m products; reducing them at native scale over a 5 590 km2 AOI is ~56
# million pixels per layer, times three reduceRegion calls. This table is a
# SUMMARY -- 250 m (the coarsest prior's scale) gives the same AOI means from
# ~90 000 pixels. Native resolution is used where it matters, in the stack
# export, not here.
covariate_table <- function(aoi_ee,
                            pts_ee = NULL,
                            registry = read_covariate_registry(),
                            imgs = NULL,
                            summary_scale = 250,
                            verbose = TRUE) {
  library(rgee)
  if (is.null(imgs)) imgs <- covariate_images(aoi_ee)

  out <- vector("list", nrow(registry))

  for (i in seq_len(nrow(registry))) {
    row <- registry[i, ]
    rec <- data.frame(
      covariate = row$covariate, asset_id = row$asset_id, band = row$band,
      role = row$role, units = row$units, native_res_m = row$native_res_m,
      temporal_window = row$temporal_window, scale_used_m = summary_scale,
      mean = NA_real_, sd = NA_real_, min = NA_real_, max = NA_real_,
      coverage_frac = NA_real_, n_valid_px = NA_real_, n_total_px = NA_real_,
      mean_at_cores = NA_real_, n_cores_with_data = NA_integer_,
      status = NA_character_, note = row$note,
      stringsAsFactors = FALSE
    )

    img <- imgs[[row$covariate]]
    if (is.null(img)) {
      rec$status <- "not built - no image for this covariate"
      out[[i]] <- rec
      next
    }
    if (verbose) message("  [", i, "/", nrow(registry), "] ", row$covariate)

    scale <- summary_scale
    band <- tryCatch(img$bandNames()$getInfo()[[1]], error = function(e) NULL)
    if (is.null(band)) {
      rec$status <- "unavailable: could not read band names"
      out[[i]] <- rec
      next
    }

    stats <- tryCatch(ee_region_stats(img, aoi_ee, scale),
                      error = function(e) structure(list(), reason = conditionMessage(e)))
    if (length(stats) == 0) {
      rec$status <- paste0("reduction failed: ", attr(stats, "reason"))
      out[[i]] <- rec
      next
    }

    pick <- function(suffix) {
      key <- grep(paste0(suffix, "$"), names(stats), value = TRUE)
      if (length(key) == 0 || is.null(stats[[key[1]]])) NA_real_ else as.numeric(stats[[key[1]]])
    }
    rec$mean <- pick("mean"); rec$sd <- pick("stdDev")
    rec$min  <- pick("min");  rec$max <- pick("max")

    cov <- tryCatch(ee_coverage_fraction(img, aoi_ee, scale), error = function(e) NULL)
    if (!is.null(cov)) {
      rec$coverage_frac <- cov$fraction
      rec$n_valid_px <- cov$n_valid
      rec$n_total_px <- cov$n_total
    }

    if (!is.null(pts_ee)) {
      vals <- tryCatch(ee_band_at_points(img, pts_ee, scale, band),
                       error = function(e) numeric(0))
      rec$n_cores_with_data <- length(vals)
      rec$mean_at_cores <- if (length(vals)) mean(vals) else NA_real_
    }

    # A categorical band has a mean, but the mean is meaningless.
    if (identical(row$covariate, "landcover")) {
      rec$mean <- NA_real_; rec$sd <- NA_real_
      rec$status <- "categorical - summarized as coverage only, mean is not meaningful"
    } else if (is.na(rec$coverage_frac)) {
      rec$status <- "summarized (coverage unknown)"
    } else if (rec$coverage_frac == 0) {
      rec$status <- "NA - no coverage over this AOI"
      rec$mean <- NA_real_; rec$sd <- NA_real_
    } else {
      rec$status <- sprintf("summarized (%.0f%% of AOI)", 100 * rec$coverage_frac)
    }

    out[[i]] <- rec
  }

  do.call(rbind, out)
}

# --- the stack --------------------------------------------------------------

#' Build the AOI stack: prior mean/sd plus every continuous covariate.
#'
#' Bands are resampled onto one grid so terra::rast() gets matching geometry,
#' the same thing run_03 does locally today.
build_aoi_stack <- function(aoi_ee,
                            prior_mean_asset = "projects/ee-cathalpdoherty2/assets/McMasterCarbon30mkgm2version1",
                            prior_sd_asset   = "projects/ee-cathalpdoherty2/assets/McMasterUncertaintyCarbon30mkgm2",
                            fill_prior_asset = "projects/ee-cathalpdoherty2/assets/McMaster_WWFCanada_soil_carbon30cm",
                            fill_prior_sd    = 18.74,
                            imgs = NULL) {
  library(rgee)
  if (is.null(imgs)) imgs <- covariate_images(aoi_ee)

  pm <- ee_image_clipped(prior_mean_asset, aoi_ee)
  ps <- ee_image_clipped(prior_sd_asset, aoi_ee)
  if (is.null(pm)) stop("prior mean asset unavailable: ", attr(pm, "reason"), call. = FALSE)
  if (is.null(ps)) stop("prior sd asset unavailable: ",   attr(ps, "reason"), call. = FALSE)

  pm <- pm$select(0)$rename("prior_mean")
  ps <- ps$select(0)$rename("prior_sd")

  # The peat prior is NoData over mineral ground and open water, so field
  # plots on mineral soil would extract nothing. Fill it with Sothe 0-30 cm:
  # average the two where both exist, take Sothe alone where peat is absent.
  # ee$ImageCollection$mean() does exactly this, because it ignores masked
  # pixels per pixel rather than propagating the mask.
  if (!is.null(fill_prior_asset) && nzchar(fill_prior_asset)) {
    fill <- ee_image_clipped(fill_prior_asset, aoi_ee)
    if (!is.null(fill)) {
      fill <- fill$select(0)$rename("prior_mean")
      pm <- ee$ImageCollection(list(pm, fill))$mean()$rename("prior_mean")

      # There is no 0-30 cm uncertainty layer in the catalogue, so where the
      # peat SD is absent it falls back to a constant -- the AOI spatial SD of
      # Sothe 0-30 cm from table 1. Stated, not derived: it does NOT represent
      # the disagreement between the two products, which is large.
      #
      # The fill is masked to where the COMBINED MEAN exists. Unmasking the
      # SD everywhere would produce pixels with an uncertainty but no
      # estimate, which is incoherent: an SD without a mean describes nothing.
      ps <- ps$unmask(fill_prior_sd)$updateMask(pm$mask())$rename("prior_sd")
    }
  }

  pm$
    addBands(ps)$
    addBands(imgs$ndvi)$
    addBands(imgs$elevation)$
    addBands(imgs$slope)$
    addBands(imgs$landcover)$
    clip(aoi_ee)
}

#' Download the stack as the GeoTIFFs the existing run_01 / run_03 scripts read.
#'
#' Written one band per file rather than one multiband file because that is what
#' those scripts already expect. `scale` is the export resolution; the workshop
#' targets a 10-30 m posterior, so 30 m is the sensible default here.
download_aoi_stack <- function(stack, aoi_ee, dir = "data", scale = 30,
                               crs = "EPSG:3857", verbose = TRUE) {
  library(rgee)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)

  # band -> filename, matching data/README.md's expected-file checklist
  files <- list(
    prior_mean = "prior_mean_10m.tif",
    prior_sd   = "prior_sd_10m.tif",
    ndvi       = "sentinel2_ndvi.tif",
    elevation  = "dem.tif",
    slope      = "slope.tif"
  )

  written <- character(0)
  for (band in names(files)) {
    dsn <- file.path(dir, files[[band]])
    if (verbose) message("  exporting ", band, " -> ", dsn)
    ok <- tryCatch({
      rgee::ee_as_rast(
        image  = stack$select(band),
        region = aoi_ee,
        dsn    = dsn,
        scale  = scale,
        crs    = crs,
        via    = "drive"
      )
      TRUE
    }, error = function(e) {
      warning("export failed for ", band, ": ", conditionMessage(e), call. = FALSE)
      FALSE
    })
    if (ok) written <- c(written, dsn)
  }

  # run_01 and run_12 want the prior at its native coarse resolution too.
  if ("prior_mean" %in% names(files)) {
    for (b in c("prior_mean", "prior_sd")) {
      dsn <- file.path(dir, paste0(b, ".tif"))
      ok <- tryCatch({
        rgee::ee_as_rast(image = stack$select(b), region = aoi_ee, dsn = dsn,
                         scale = 250, crs = crs, via = "drive")
        TRUE
      }, error = function(e) FALSE)
      if (ok) written <- c(written, dsn)
    }
  }

  written
}
