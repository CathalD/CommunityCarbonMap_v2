# Step 2 -- Process and harmonize the ground data
#
# Question: what did we actually measure in the field, and how do we turn it
# into the variable we want to map?
#
# Field intervals rarely line up with modelling intervals. Where a target
# interval overlaps a measured layer, that layer contributes in proportion to
# how much of the target it covers:
#
#   stock(target) = SUM over layers of  stock(layer) x overlap / layer thickness
#
# This is mass-preserving, which is what a STOCK needs. Interpolating the
# concentration with a spline and averaging it is not -- it gives a plausible
# curve that does not conserve carbon. Concentration and bulk density are
# reported here too, as overlap-weighted means, because those are intensive
# properties and averaging them is the right operation.
#
# Written in base R rather than soilassessment::depthharm() on purpose. This is
# the same arithmetic as sheet 3 of data/soil_carbon_calculation.xlsx, so the
# spreadsheet and the code can be checked against each other line by line --
# which is the whole premise of the workshop.
#
# A core that stops short of a target interval is NOT dropped. It reports the
# fraction of the interval it actually covers, so the decision about whether to
# use it stays downstream where it belongs.

harmonize_core_depths <- function(soil_data,
                                  target_depths = c(0, 15, 30, 50, 100),
                                  id_col = "plot_id",
                                  top_col = "depth_from",
                                  bottom_col = "depth_to",
                                  soc_col = "soc",
                                  bd_col = "bulk_density",
                                  cf_col = "coarse_frag") {

  d <- as.data.frame(soil_data)
  id  <- as.character(d[[id_col]])
  top <- as.numeric(d[[top_col]])
  bot <- as.numeric(d[[bottom_col]])
  soc <- as.numeric(d[[soc_col]])
  bd  <- as.numeric(d[[bd_col]])
  cf  <- if (!is.null(d[[cf_col]])) as.numeric(d[[cf_col]]) else rep(0, nrow(d))
  cf[is.na(cf)] <- 0

  thickness <- bot - top

  # kg C/m2 for each MEASURED layer.
  #   soc (g/kg) / 1000  ->  g C per g soil
  #   x bulk density (g/cm3) x thickness (cm)  ->  g C/cm2
  #   x 10  ->  kg C/m2
  # which reduces to soc x bd x thickness / 100.
  layer_stock <- soc * bd * thickness * (1 - cf) / 100

  cores <- unique(id)
  n_targets <- length(target_depths) - 1
  out <- vector("list", length(cores) * n_targets)
  k <- 0

  for (core in cores) {
    rows <- which(id == core)
    for (i in seq_len(n_targets)) {
      t0 <- target_depths[i]
      t1 <- target_depths[i + 1]

      overlap <- pmax(0, pmin(bot[rows], t1) - pmax(top[rows], t0))
      covered <- sum(overlap)
      w <- overlap / thickness[rows]          # fraction of each layer used

      k <- k + 1
      out[[k]] <- data.frame(
        plot_id       = core,
        top           = t0,
        bottom        = t1,
        stock_kg_m2   = if (covered > 0) sum(layer_stock[rows] * w) else NA_real_,
        soc           = if (covered > 0) sum(soc[rows] * overlap) / covered else NA_real_,
        bulk_density  = if (covered > 0) sum(bd[rows]  * overlap) / covered else NA_real_,
        covered_cm    = covered,
        coverage_frac = covered / (t1 - t0),
        stringsAsFactors = FALSE
      )
    }
  }

  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}
