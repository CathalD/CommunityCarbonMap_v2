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

  # Plots with a NoData prior have no residual; the spatial tests below cannot
  # accept them, and silently passing NA into moran.test() just errors deeper in.
  ok <- is.finite(field_sf$residual)
  usable <- field_sf[ok, ]

  out <- list(plot = p, n_usable = sum(ok), n_dropped = sum(!ok))

  if (run_moran) {
    if (nrow(usable) < 5) {
      out$moran <- paste0("skipped: ", nrow(usable),
                          " usable residuals is too few for Moran's I")
    } else {
      library(spdep)
      # k must stay well under n or the neighbour graph is nearly complete and
      # the test is meaningless.
      k <- max(1, min(4, floor((nrow(usable) - 1) / 3)))
      nb <- knn2nb(knearneigh(sf::st_coordinates(usable), k = k))
      out$moran <- moran.test(usable$residual, nb2listw(nb))
      out$moran_k <- k
    }
  }

  if (run_variogram) {
    if (nrow(usable) < 15) {
      out$variogram <- paste0("skipped: ", nrow(usable),
                              " usable residuals is too few to fit a variogram")
    } else {
      library(gstat)
      out$variogram <- variogram(residual ~ 1, data = usable)
    }
  }

  out
}
