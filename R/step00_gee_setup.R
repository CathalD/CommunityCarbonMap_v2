# Step 0 (setup) -- authenticate Earth Engine, ingest the AOI and the core
# locations, and give every later function one place to get them from.
#
# Everything downstream is clipped to the AOI. That is not cosmetic: the AOI is
# a few thousand km2 against wall-to-wall Canadian and global products, so
# clipping first is the difference between a reduction that returns and one
# that times out.

# `drive = TRUE` is required before any raster download: ee_as_rast() sends
# anything larger than a getInfo request through Google Drive, and that needs
# the Drive credential attached at init time. It triggers a one-off browser
# consent the first time.
gee_init <- function(project = Sys.getenv("GEE_PROJECT", "ee-cathalpdoherty2"),
                     drive = FALSE,
                     quiet = FALSE) {
  library(rgee)

  # rgee gained the `project` argument fairly late; fall back for older installs.
  ok <- tryCatch({
    rgee::ee_Initialize(project = project, drive = drive)
    TRUE
  }, error = function(e) {
    if (!quiet) message("ee_Initialize(project=) failed: ", conditionMessage(e))
    FALSE
  })

  if (!ok) {
    ok <- tryCatch({
      rgee::ee_Initialize(drive = drive)
      TRUE
    }, error = function(e) {
      stop(
        "Earth Engine would not initialize.\n",
        "  1. install the backend once:  rgee::ee_install()\n",
        "  2. authenticate once:         rgee::ee_Authenticate()\n",
        "  3. set your cloud project:    Sys.setenv(GEE_PROJECT = 'your-project')\n",
        "Original error: ", conditionMessage(e),
        call. = FALSE
      )
    })
  }

  if (!quiet) message("Earth Engine initialized (project: ", project, ")")
  invisible(project)
}

# --- AOI --------------------------------------------------------------------

load_aoi <- function(path = "data/aoi.geojson") {
  library(sf)
  aoi <- sf::st_read(path, quiet = TRUE)
  if (is.na(sf::st_crs(aoi))) sf::st_crs(aoi) <- 4326
  sf::st_make_valid(aoi)
}

# Area in km2, computed on the ellipsoid so the geographic CRS is not a problem.
aoi_area_km2 <- function(aoi) {
  as.numeric(sum(sf::st_area(aoi))) / 1e6
}

aoi_to_ee <- function(aoi) {
  library(rgee)
  # sf_as_ee() returns an ee$Geometry for an sfc and an ee$FeatureCollection for
  # an sf data.frame. Union first so this is always a single geometry.
  rgee::sf_as_ee(sf::st_union(sf::st_geometry(aoi)))
}

# _targets.R and run_01 read data/aoi.gpkg; the practitioner supplied
# data/aoi.geojson. Write the gpkg from the geojson so both names point at the
# same polygon instead of one of them being missing.
write_aoi_gpkg <- function(aoi = load_aoi(), dsn = "data/aoi.gpkg") {
  library(sf)
  sf::st_write(aoi, dsn, delete_dsn = TRUE, quiet = TRUE)
  dsn
}

# --- Core locations ---------------------------------------------------------

# One point per core, from the raw slice table. Longitudes are forced negative
# (western hemisphere) -- GPS exports sometimes drop the sign, and a positive
# longitude quietly places the cores on the other side of the planet.
load_core_points <- function(path = "data/example_soil_cores.csv") {
  library(sf)
  d <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)

  pts <- data.frame(
    core_id   = d[["Core Id"]],
    year      = d[["year"]],
    latitude  = d[["Latitude"]],
    longitude = -abs(d[["Longitude"]]),
    stringsAsFactors = FALSE
  )
  pts <- pts[!duplicated(pts$core_id), ]

  sf::st_as_sf(pts, coords = c("longitude", "latitude"), crs = 4326,
               remove = FALSE)
}

core_points_to_ee <- function(pts) {
  library(rgee)
  rgee::sf_as_ee(pts)
}

# --- Small helpers used by every table function -----------------------------

# Resolve an asset id to an ee$Image regardless of how it was published, and
# clip it to the AOI immediately. Returns NULL (with a reason attached) rather
# than erroring, so one unreachable private asset cannot abort the whole table.
ee_image_clipped <- function(asset_id, aoi_ee) {
  library(rgee)

  info <- tryCatch(ee$data$getAsset(asset_id), error = function(e) NULL)
  if (is.null(info)) {
    return(structure(NULL, reason = "asset not found or not readable by this account"))
  }

  img <- switch(
    info$type,
    "IMAGE"            = ee$Image(asset_id),
    "IMAGE_COLLECTION" = ee$ImageCollection(asset_id)$mosaic(),
    structure(NULL, reason = paste0("asset type ", info$type, " is not an image"))
  )
  if (is.null(img)) return(img)

  img$clip(aoi_ee)
}

# mean / sd / min / max over the AOI in one round trip.
ee_region_stats <- function(img, aoi_ee, scale, max_pixels = 1e10) {
  library(rgee)
  red <- ee$Reducer$mean()$
    combine(reducer2 = ee$Reducer$stdDev(), sharedInputs = TRUE)$
    combine(reducer2 = ee$Reducer$minMax(), sharedInputs = TRUE)
  img$reduceRegion(
    reducer   = red,
    geometry  = aoi_ee,
    scale     = scale,
    maxPixels = max_pixels,
    bestEffort = TRUE
  )$getInfo()
}

# Fraction of the AOI where the layer actually has data. A peat-only prior is
# NoData over mineral ground and open water, so this is the number that decides
# whether a "mean over the AOI" means anything at all.
ee_coverage_fraction <- function(img, aoi_ee, scale, max_pixels = 1e10) {
  library(rgee)
  n_valid <- img$select(0)$reduceRegion(
    reducer = ee$Reducer$count(), geometry = aoi_ee, scale = scale,
    maxPixels = max_pixels, bestEffort = TRUE
  )$getInfo()
  n_total <- ee$Image$constant(1)$rename("all")$reduceRegion(
    reducer = ee$Reducer$count(), geometry = aoi_ee, scale = scale,
    maxPixels = max_pixels, bestEffort = TRUE
  )$getInfo()

  valid <- as.numeric(n_valid[[1]])
  total <- as.numeric(n_total[["all"]])
  list(
    n_valid = valid,
    n_total = total,
    fraction = if (is.na(total) || total == 0) NA_real_ else valid / total
  )
}

# Value of a layer at each core location -- the first look at whether the prior
# and the ground data are even in the same numeric range. Parsed straight out of
# getInfo() rather than via ee_as_sf(), because sampleRegions() with
# geometries = FALSE returns features sf cannot build a geometry column from.
ee_band_at_points <- function(img, pts_ee, scale, band) {
  library(rgee)
  fc <- img$select(band)$sampleRegions(
    collection = pts_ee, scale = scale, geometries = FALSE
  )
  info <- tryCatch(fc$getInfo(), error = function(e) NULL)
  if (is.null(info) || length(info$features) == 0) return(numeric(0))

  vals <- vapply(info$features, function(f) {
    v <- f$properties[[band]]
    if (is.null(v)) NA_real_ else as.numeric(v)
  }, numeric(1))
  vals[!is.na(vals)]
}
