# Step 5 -- Spatial residual analysis
#
# Question: where is the prior wrong?
#
# Start extremely simple: plot the residuals in space. Only if there's
# visible structure, optionally run Moran's I (spdep) or a variogram
# (gstat). Do NOT interpolate the residuals in Version 1 -- that would hide
# the raw pattern we most need to look at directly.

spatial_residual_diagnostics <- function(field_sf, run_moran = FALSE, run_variogram = FALSE) {
  library(ggplot2)

  p <- ggplot(field_sf) +
    geom_sf(aes(colour = residual)) +
    scale_colour_gradient2(low = "#2F5233", mid = "grey90", high = "#93392A")

  out <- list(plot = p)

  if (run_moran) {
    library(spdep)
    nb <- knn2nb(knearneigh(sf::st_coordinates(field_sf), k = 4))
    lw <- nb2listw(nb)
    out$moran <- moran.test(field_sf$residual, lw)
  }

  if (run_variogram) {
    library(gstat)
    out$variogram <- variogram(residual ~ 1, data = field_sf)
  }

  out
}
