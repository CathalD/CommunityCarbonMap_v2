# Step 0 (visuals) -- look at every layer, clipped to the AOI, as we go.
#
# Two ways to look, because they answer different questions:
#   view_aoi_layer()  interactive slippy map in the browser (rgee's Map$).
#                     Good for "is this layer where I think it is, and does it
#                     have holes?".
#   plot_aoi_raster() static plot of a downloaded GeoTIFF via terra. Good for
#                     the record, and it works with no Earth Engine session.
#
# Clipping is not decoration. An unclipped Map$addLayer() of a wall-to-wall
# Canadian product renders tiles for all of Canada; clipped to the AOI it
# renders a few.

source_once_vis <- function(path) if (!exists("gee_init")) source(path)
source_once_vis("R/step00_gee_setup.R")

# Palettes kept in one place so the prior, the posterior and the difference
# maps stay comparable across steps 0, 11 and 13.
CARBON_PALETTE <- c("#f7f4e9", "#d9c99a", "#a3874b", "#6b5a2e", "#3a3018")
UNCERTAINTY_PALETTE <- c("#ffffcc", "#fed976", "#fd8d3c", "#e31a1c", "#800026")
NDVI_PALETTE <- c("#ad4f34", "#e8e3b0", "#7aa457", "#2f5233")

#' Add one Earth Engine image to an interactive map, clipped to the AOI.
#'
#' @param img    ee$Image (clipped or not -- it gets clipped here regardless)
#' @param aoi_ee AOI geometry
#' @param name   layer name in the map's layer control
#' @param vis    list(min=, max=, palette=); guessed from the data if NULL
view_aoi_layer <- function(img, aoi_ee, name, vis = NULL,
                           palette = CARBON_PALETTE, scale = 250) {
  library(rgee)

  img <- img$clip(aoi_ee)

  if (is.null(vis)) {
    # Stretch to the 2nd/98th percentile inside the AOI so one extreme pixel
    # does not flatten the whole image to a single colour.
    pct <- tryCatch(
      img$select(0)$reduceRegion(
        reducer = ee$Reducer$percentile(c(2, 98)),
        geometry = aoi_ee, scale = scale, maxPixels = 1e10, bestEffort = TRUE
      )$getInfo(),
      error = function(e) NULL
    )
    lo <- if (is.null(pct)) 0 else as.numeric(pct[[1]])
    hi <- if (is.null(pct) || length(pct) < 2) 1 else as.numeric(pct[[2]])
    if (!is.finite(lo) || !is.finite(hi) || hi <= lo) { lo <- 0; hi <- 1 }
    vis <- list(min = lo, max = hi, palette = palette)
  }

  Map$centerObject(aoi_ee, zoom = 8)
  Map$addLayer(eeObject = img, visParams = vis, name = name)
}

#' The whole step-0 picture in one interactive map.
#'
#' Prior mean, prior uncertainty, NDVI and elevation, plus the AOI outline and
#' the core locations, all clipped. Layers stack, so toggle them in the control.
view_aoi_stack <- function(stack, aoi_ee, pts_ee = NULL, aoi_sf = NULL) {
  library(rgee)

  bands <- tryCatch(stack$bandNames()$getInfo(), error = function(e) character(0))

  m <- NULL
  add <- function(m, layer) if (is.null(m)) layer else m + layer

  if ("prior_mean" %in% bands) {
    m <- add(m, view_aoi_layer(stack$select("prior_mean"), aoi_ee,
                               "prior mean (kg C/m2)", palette = CARBON_PALETTE))
  }
  if ("prior_sd" %in% bands) {
    m <- add(m, view_aoi_layer(stack$select("prior_sd"), aoi_ee,
                               "prior uncertainty (kg C/m2)",
                               palette = UNCERTAINTY_PALETTE))
  }
  if ("ndvi" %in% bands) {
    m <- add(m, view_aoi_layer(stack$select("ndvi"), aoi_ee, "NDVI",
                               vis = list(min = 0, max = 0.9, palette = NDVI_PALETTE),
                               scale = 10))
  }
  if ("elevation" %in% bands) {
    m <- add(m, view_aoi_layer(stack$select("elevation"), aoi_ee, "elevation (m)",
                               palette = c("#2b2b2b", "#f0f0f0"), scale = 30))
  }

  if (!is.null(aoi_sf)) {
    m <- add(m, Map$addLayer(rgee::sf_as_ee(sf::st_geometry(aoi_sf)),
                             list(color = "red"), "AOI"))
  }
  if (!is.null(pts_ee)) {
    m <- add(m, Map$addLayer(pts_ee, list(color = "black"), "community cores"))
  }
  m
}

#' Static plot of a downloaded stack band, with the AOI and cores on top.
#'
#' The offline counterpart to view_aoi_layer() -- needs no Earth Engine session,
#' so it still works when re-running the analysis from the downloaded GeoTIFFs.
plot_aoi_raster <- function(path, aoi = NULL, pts = NULL, main = basename(path),
                            palette = CARBON_PALETTE) {
  library(terra)
  r <- terra::rast(path)

  if (!is.null(aoi)) {
    aoi_v <- terra::vect(sf::st_transform(aoi, terra::crs(r)))
    r <- terra::mask(terra::crop(r, aoi_v), aoi_v)
  }

  terra::plot(r, main = main, col = grDevices::colorRampPalette(palette)(100))
  if (!is.null(aoi)) terra::lines(aoi_v, col = "red", lwd = 2)
  if (!is.null(pts)) {
    terra::points(terra::vect(sf::st_transform(pts, terra::crs(r))),
                  pch = 21, bg = "white", cex = 1.1)
  }
  invisible(r)
}

#' Save every downloaded band as a PNG under outputs/figures/.
plot_stack_to_png <- function(files, aoi = NULL, pts = NULL,
                              dir = "outputs/figures", width = 1400, height = 1100) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  written <- character(0)
  for (f in files) {
    if (!file.exists(f)) next
    png_path <- file.path(dir, sub("\\.tif$", ".png", basename(f)))
    pal <- if (grepl("sd|uncert", f)) UNCERTAINTY_PALETTE else
      if (grepl("ndvi", f)) NDVI_PALETTE else CARBON_PALETTE

    # try() keeps one unplottable band from aborting the rest, and means the
    # device is always closed exactly once.
    grDevices::png(png_path, width = width, height = height, res = 150)
    try(plot_aoi_raster(f, aoi = aoi, pts = pts, palette = pal), silent = TRUE)
    grDevices::dev.off()
    written <- c(written, png_path)
  }
  written
}
