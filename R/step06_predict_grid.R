# Step 14 -- prediction grid and posterior surfaces.
#
# Produces E[Z(s)|data] and SD[Z(s)|data] together. Never the mean alone: in an
# MRV context the uncertainty surface is what tells a council where the map can
# and cannot be relied on.
#
# GRID RESOLUTION IS A STATISTICAL CHOICE, NOT A MEMORY WORKAROUND.
# posterior_epred() costs grid_cells x draws x training_points, so a 30 m grid
# over this AOI (40 M cells) x 200 draws is ~64 GB and will kill the session.
# But the honest reason for a coarse grid is that eight cores cannot support a
# 30 m map: the GP length scale is prior-dominated, so a fine grid interpolates
# smoothly between a handful of points and LOOKS far more certain than the data
# warrants. A 1-2 km grid shows what is actually known.

#' Build a prediction grid over the AOI, in a projected CRS.
#'
#' @param crs target CRS. Must be equal-distance-ish: the repo's rasters are
#'   EPSG:3857, where at 56 N one map metre is only ~0.56 ground metres, so
#'   distances -- and therefore any GP length scale -- are distorted by ~1.8x.
#'   Use the local UTM zone instead.
build_prediction_grid <- function(aoi, cellsize = 1000, crs = 32616) {
  library(sf)

  aoi_proj <- sf::st_transform(sf::st_geometry(aoi), crs)
  centres  <- sf::st_make_grid(aoi_proj, cellsize = cellsize, what = "centers")
  centres  <- centres[sf::st_intersects(centres, aoi_proj, sparse = FALSE)[, 1]]

  grid <- sf::st_as_sf(centres)
  # st_as_sf() on a bare sfc names the geometry column "x". Renaming it BEFORE
  # adding x/y coordinate columns is not optional -- otherwise the mutate below
  # overwrites the geometry with a numeric vector, and the sf class attribute
  # still points at "x", so later geom_sf()/st_geometry() calls fail with the
  # opaque "sf_column does not point to a geometry column".
  sf::st_geometry(grid) <- "geometry"

  xy <- sf::st_coordinates(grid)
  grid$x <- xy[, 1]
  grid$y <- xy[, 2]
  grid
}

#' Sample the covariate rasters onto the grid.
#'
#' Reuses the repo's existing covariate stack -- no new extraction logic.
#' `stack` should be the same SpatRaster steps 3 and 8b build.
attach_grid_covariates <- function(grid, stack, names_out = NULL) {
  library(terra)
  library(sf)

  pts  <- terra::vect(sf::st_transform(grid, terra::crs(stack)))
  vals <- terra::extract(stack, pts)[, -1, drop = FALSE]
  if (!is.null(names_out)) names(vals) <- names_out

  for (nm in names(vals)) grid[[nm]] <- vals[[nm]]

  missing <- vapply(names(vals), function(nm) sum(is.na(grid[[nm]])), numeric(1))
  if (any(missing > 0)) {
    message("grid cells with no covariate value: ",
            paste(sprintf("%s=%d", names(missing), missing), collapse = ", "),
            " of ", nrow(grid))
  }
  grid
}

#' Posterior mean and SD surfaces from a fitted brms model.
#'
#' `ndraws` subsets the posterior to keep memory bounded. 200 is enough to
#' check the mechanics; a reported uncertainty surface should use more.
posterior_surface <- function(fit, grid, ndraws = 200, chunk = 5000) {
  library(brms)

  # Draws are generated immediately before summarising and the grid is not
  # reordered in between -- any filter/arrange/mutate here silently desyncs the
  # rows of `posterior` from the rows of `grid`.
  n <- nrow(grid)
  mean_v <- numeric(n)
  sd_v   <- numeric(n)

  starts <- seq(1, n, by = chunk)
  for (s in starts) {
    idx <- s:min(s + chunk - 1, n)
    draws <- brms::posterior_epred(
      fit, newdata = sf::st_drop_geometry(grid)[idx, , drop = FALSE],
      ndraws = ndraws, allow_new_levels = TRUE
    )
    mean_v[idx] <- apply(draws, 2, mean)
    sd_v[idx]   <- apply(draws, 2, stats::sd)
  }

  grid$SOC_mean <- mean_v
  grid$SOC_sd   <- sd_v
  grid$SOC_cv   <- ifelse(grid$SOC_mean > 0, grid$SOC_sd / grid$SOC_mean, NA_real_)
  grid
}

#' The two maps, side by side. Presenting the mean alone is not an option.
plot_posterior_surface <- function(grid, cores = NULL,
                                   unit = "kg C/m2") {
  library(ggplot2)

  base <- function(fill, title, legend, palette) {
    p <- ggplot(grid) +
      geom_sf(aes(colour = .data[[fill]]), size = 1.2) +
      scale_colour_gradientn(colours = palette) +
      labs(title = title, colour = legend) +
      theme_minimal()
    if (!is.null(cores)) {
      p <- p + geom_sf(data = cores, shape = 21, fill = "white",
                       colour = "black", size = 2)
    }
    p
  }

  list(
    mean = base("SOC_mean", "Posterior soil carbon  E[Z(s) | data]", unit,
                c("#f7f4e9", "#d9c99a", "#a3874b", "#6b5a2e", "#3a3018")),
    sd   = base("SOC_sd", "Posterior uncertainty  SD[Z(s) | data]", unit,
                c("#ffffcc", "#fed976", "#fd8d3c", "#e31a1c", "#800026"))
  )
}
