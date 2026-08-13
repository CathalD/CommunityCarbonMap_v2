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
#
# EXTRAPOLATION. Below the deepest measured layer, carbon density is continued
# with a simple exponential decay so a 30 cm core can be compared against 0-30
# and 0-100 cm products:
#
#   rho(d) = rho_bottom x exp(-k (d - z_bottom))
#
# The curve is ANCHORED at the deepest observed density rather than at a fitted
# intercept, so it is continuous with the real data -- "extrapolate from the
# last observed sample". Its integral over a target interval is closed-form:
#
#   stock = (rho_bottom / k) x [ exp(-k(z1 - z_b)) - exp(-k(z2 - z_b)) ]
#
# k is fitted per core by regressing log(density) on layer midpoint. Two guards
# matter: a core with one layer cannot be fitted, and peat profiles often have
# density INCREASING with depth (a negative k), which would make the
# extrapolation explode. In both cases k falls back to decay_k_default.
#
# Extrapolated carbon is reported in its own column. Measured and modelled
# carbon never get silently added together.

# Fit the decay constant k (per cm) from one core's layer densities.
# Falls back to k_default when there is nothing to fit or the profile gets
# denser with depth, which is normal in peat and would otherwise give k <= 0.
fit_decay_k <- function(mid, rho, k_default) {
  ok <- is.finite(mid) & is.finite(rho) & rho > 0
  if (sum(ok) < 2) return(k_default)
  k <- -unname(stats::coef(stats::lm(log(rho[ok]) ~ mid[ok]))[2])
  if (!is.finite(k) || k <= 0) k_default else k
}

harmonize_core_depths <- function(soil_data,
                                  target_depths = c(0, 15, 30, 50, 100),
                                  id_col = "plot_id",
                                  top_col = "depth_from",
                                  bottom_col = "depth_to",
                                  soc_col = "soc",
                                  bd_col = "bulk_density",
                                  cf_col = "coarse_frag",
                                  extrapolate = TRUE,
                                  decay_k = NULL,
                                  decay_k_default = 0.0587) {

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

  j <- 0
  for (core in cores) {
    rows <- which(id == core)
    rows <- rows[order(top[rows])]

    # carbon density of each measured layer, kg C/m2 per cm
    rho <- layer_stock[rows] / thickness[rows]
    mid <- (top[rows] + bot[rows]) / 2

    z_bottom <- max(bot[rows])
    rho_bottom <- rho[length(rows)]
    kk <- if (!is.null(decay_k)) decay_k else fit_decay_k(mid, rho, decay_k_default)

    for (i in seq_len(n_targets)) {
      t0 <- target_depths[i]
      t1 <- target_depths[i + 1]

      overlap <- pmax(0, pmin(bot[rows], t1) - pmax(top[rows], t0))
      covered <- sum(overlap)
      w <- overlap / thickness[rows]          # fraction of each layer used

      # the part of this interval that lies below the deepest measurement
      e0 <- max(t0, z_bottom)
      e1 <- max(t1, z_bottom)
      extra_cm <- e1 - e0
      extra <- 0
      if (extrapolate && extra_cm > 0 && is.finite(rho_bottom) && rho_bottom > 0) {
        extra <- (rho_bottom / kk) *
          (exp(-kk * (e0 - z_bottom)) - exp(-kk * (e1 - z_bottom)))
      }

      measured <- if (covered > 0) sum(layer_stock[rows] * w) else NA_real_

      j <- j + 1
      out[[j]] <- data.frame(
        plot_id        = core,
        top            = t0,
        bottom         = t1,
        stock_kg_m2    = measured,
        soc            = if (covered > 0) sum(soc[rows] * overlap) / covered else NA_real_,
        bulk_density   = if (covered > 0) sum(bd[rows]  * overlap) / covered else NA_real_,
        covered_cm     = covered,
        coverage_frac  = covered / (t1 - t0),
        extrapolated_kg_m2 = extra,
        extrapolated_cm    = extra_cm,
        stock_total_kg_m2  = sum(c(measured, extra), na.rm = TRUE),
        decay_k        = kk,
        stringsAsFactors = FALSE
      )
    }
  }

  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}
