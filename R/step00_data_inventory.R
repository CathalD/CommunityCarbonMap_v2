# Step 0 -- What do we know?
#
# Question: before any modelling, what information already exists, and what does
# each piece actually represent (estimate, uncertainty, spatial support)?
#
# Same five columns as before; the numbers are now real. build_data_inventory()
# folds the three step-0 tables into the one inventory the workshop asks for:
#
#   table 1  prior_map_table()    what the carbon maps say
#   table 2  covariate_table()    what covariates we have
#   table 3  open_ground_table()  what other open ground data exists
#
# The rule the workshop states, and this function enforces: no mean/uncertainty
# available means NA and a reason, never a blank and never an invented number.

#' @param priors     table 1, or NULL to leave the map rows out
#' @param covariates table 2, or NULL
#' @param ground     table 3, or NULL
#' @param cores      summarize_community_cores(), or NULL
#' @param aoi        sf AOI, used for the AOI row's spatial support
build_data_inventory <- function(priors = NULL,
                                 covariates = NULL,
                                 ground = NULL,
                                 cores = NULL,
                                 aoi = NULL) {

  row_of <- function(dataset, mean_estimate, uncertainty, data_type,
                     spatial_support, depth_basis = NA_character_,
                     units = NA_character_, coverage = NA_real_,
                     source = NA_character_, note = NA_character_) {
    data.frame(
      dataset = dataset,
      mean_estimate = mean_estimate,
      uncertainty = uncertainty,
      data_type = data_type,
      spatial_support = spatial_support,
      depth_basis = depth_basis,
      units = units,
      aoi_coverage_frac = coverage,
      source = source,
      note = note,
      stringsAsFactors = FALSE
    )
  }

  out <- list()

  # --- the AOI itself -------------------------------------------------------
  if (!is.null(aoi)) {
    out[[length(out) + 1]] <- row_of(
      "Area of interest", NA_real_, NA_real_, "vector",
      sprintf("polygon, %.0f km2", aoi_area_km2(aoi)),
      source = "data/aoi.geojson",
      note = "Fort Severn study area, supplied by practitioner"
    )
  }

  # --- table 1: prior carbon maps -------------------------------------------
  # An uncertainty layer's AOI mean is the typical PIXEL uncertainty, not the
  # uncertainty of the AOI mean -- step 1b. It is carried in the uncertainty
  # column of its paired mean row, and its own row keeps mean_estimate NA.
  if (!is.null(priors)) {
    unc <- priors[priors$role == "prior_uncertainty", , drop = FALSE]

    for (i in seq_len(nrow(priors))) {
      p <- priors[i, ]
      if (identical(p$role, "prior_uncertainty")) next

      # Pair on the registry's explicit pairs_with column, never on name
      # similarity. This is what stops the Sothe 0-30 cm stock from silently
      # borrowing the 0-1 m uncertainty layer, which the catalogue warns
      # against: it has no 0-30 cm uncertainty, so NA is the honest answer.
      pair_sd <- NA_real_
      if (!is.null(p$pairs_with) && !is.na(p$pairs_with) && nrow(unc)) {
        pair <- unc[!is.na(unc$dataset) & unc$dataset == p$pairs_with, , drop = FALSE]
        if (nrow(pair) == 1) pair_sd <- pair$mean
      }

      out[[length(out) + 1]] <- row_of(
        p$product, p$mean, pair_sd, "raster",
        if (is.na(p$native_res_m)) "not applicable" else paste0(p$native_res_m, " m"),
        depth_basis = p$depth_basis, units = p$units,
        coverage = p$coverage_frac, source = p$asset_id,
        note = paste0(p$status, ". ", p$note)
      )
    }

    # uncertainty layers get their own row too, so a reader can see the layer
    # exists and what its typical pixel value is
    for (i in seq_len(nrow(unc))) {
      u <- unc[i, ]
      out[[length(out) + 1]] <- row_of(
        paste0(u$product, " -- uncertainty layer"), NA_real_, u$mean, "raster",
        if (is.na(u$native_res_m)) "not applicable" else paste0(u$native_res_m, " m"),
        depth_basis = u$depth_basis, units = u$units,
        coverage = u$coverage_frac, source = u$asset_id,
        note = paste0("Typical PIXEL uncertainty, not the uncertainty of the ",
                      "AOI mean. ", u$status, ". ", u$note)
      )
    }
  }

  # --- table 2: covariates --------------------------------------------------
  if (!is.null(covariates)) {
    for (i in seq_len(nrow(covariates))) {
      cv <- covariates[i, ]
      out[[length(out) + 1]] <- row_of(
        cv$covariate, cv$mean, cv$sd, "raster",
        if (is.na(cv$native_res_m)) "not applicable" else paste0(cv$native_res_m, " m"),
        units = cv$units, coverage = cv$coverage_frac, source = cv$asset_id,
        note = paste0(cv$status, ". ", cv$note)
      )
    }
  }

  # --- table 3: other open ground data --------------------------------------
  if (!is.null(ground)) {
    for (i in seq_len(nrow(ground))) {
      g <- ground[i, ]
      support <- if (is.na(g$n_features_in_aoi)) {
        "point / profile"
      } else {
        sprintf("point / profile (%.0f in AOI)", g$n_features_in_aoi)
      }
      out[[length(out) + 1]] <- row_of(
        g$product, g$mean, g$sd, "ground", support,
        depth_basis = g$depth_basis, units = g$units,
        source = if (is.na(g$asset_id)) g$source else g$asset_id,
        note = paste0(g$status, ". ", g$note)
      )
    }
  }

  # --- the community cores --------------------------------------------------
  if (!is.null(cores)) {
    out[[length(out) + 1]] <- row_of(
      "Community soil cores (this project)",
      cores$mean_kg_m2, cores$sd_kg_m2, "ground",
      sprintf("core / plot (%d cores, %d with full depth coverage)",
              cores$n_cores, cores$n_full_coverage),
      depth_basis = cores$depth_basis, units = "kg C/m2", coverage = NA_real_,
      source = "data/community_soil_cores.csv via data/soil_carbon_calculation.xlsx",
      note = paste0(
        "Mean and SD over full-coverage cores only. Partial cores are excluded ",
        "because a core that stops short of the target depth is not an ",
        "observation of that interval."
      )
    )
  }

  if (length(out) == 0) {
    warning("build_data_inventory() got no inputs -- run scripts/run_00_data_inventory.R ",
            "first to produce the three step-0 tables.", call. = FALSE)
    return(row_of(character(0), numeric(0), numeric(0), character(0), character(0)))
  }

  inv <- do.call(rbind, out)
  rownames(inv) <- NULL
  inv
}
