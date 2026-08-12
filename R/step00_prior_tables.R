# Step 0, TABLE 1 -- what the carbon maps say over our AOI.
#
# One row per product in data/prior_assets.csv (which is the machine-readable
# form of data/CarbonResources_Assets+Covariates). Products with no Earth
# Engine asset still get a row, with NA and the reason -- the workshop's rule is
# that a missing number is written down as NA, never left blank and never
# invented.
#
# Every image is clipped to the AOI before it is reduced.

source_once <- function(path) if (!exists("gee_init")) source(path)
source_once("R/step00_gee_setup.R")

read_prior_registry <- function(path = "data/prior_assets.csv") {
  utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
}

# --- SoilGrids: build the 0-30 cm stock rather than use the packaged one -----
#
# Built from soc_mean + bdod_mean so the depth integration matches the one
# applied to the field cores in data/soil_carbon_calculation.xlsx:
#   (soc/10) x (bdod/100) x thickness_cm / 100 = kg C/m2
# soc_mean is dg/kg (hence /10 -> g/kg) and bdod_mean is cg/cm3 (hence /100).
soilgrids_stock_0_30 <- function(aoi_ee) {
  library(rgee)
  soc <- ee$Image("projects/soilgrids-isric/soc_mean")$clip(aoi_ee)
  bd  <- ee$Image("projects/soilgrids-isric/bdod_mean")$clip(aoi_ee)

  bands <- list(
    list(soc = "soc_0-5cm_mean",   bd = "bdod_0-5cm_mean",   thickness = 5),
    list(soc = "soc_5-15cm_mean",  bd = "bdod_5-15cm_mean",  thickness = 10),
    list(soc = "soc_15-30cm_mean", bd = "bdod_15-30cm_mean", thickness = 15)
  )

  have <- soc$bandNames()$getInfo()
  want <- vapply(bands, function(b) b$soc, character(1))
  if (!all(want %in% have)) {
    stop("SoilGrids band names have changed. Expected ", paste(want, collapse = ", "),
         "\n  found: ", paste(have, collapse = ", "), call. = FALSE)
  }

  stock <- NULL
  for (b in bands) {
    layer <- soc$select(b$soc)$divide(10)$
      multiply(bd$select(b$bd)$divide(100))$
      multiply(b$thickness)$divide(100)
    stock <- if (is.null(stock)) layer else stock$add(layer)
  }
  stock$rename("soilgrids_0_30cm_stock")
}

# Resolve one registry row to a clipped ee$Image, or NULL with a reason.
prior_image <- function(row, aoi_ee) {
  if (!is.na(row$derive) && nzchar(row$derive)) {
    img <- tryCatch(
      switch(row$derive,
             "soilgrids_stock_0_30" = soilgrids_stock_0_30(aoi_ee),
             stop("unknown derive rule: ", row$derive)),
      error = function(e) structure(NULL, reason = conditionMessage(e))
    )
    return(img)
  }
  ee_image_clipped(row$asset_id, aoi_ee)
}

#' Table 1 -- prior carbon maps summarized over the AOI
#'
#' @param aoi_ee   AOI geometry from aoi_to_ee()
#' @param pts_ee   core locations from core_points_to_ee(), or NULL to skip
#' @param registry data.frame from read_prior_registry()
#' @param scale_override reduce everything at this scale (m) instead of each
#'   asset's native resolution. Useful to force a common spatial support.
prior_map_table <- function(aoi_ee,
                            pts_ee = NULL,
                            registry = read_prior_registry(),
                            scale_override = NULL,
                            verbose = TRUE) {
  library(rgee)

  keep <- registry$role %in% c("prior_mean", "prior_uncertainty", "no_asset")
  registry <- registry[keep, , drop = FALSE]

  out <- vector("list", nrow(registry))

  for (i in seq_len(nrow(registry))) {
    row <- registry[i, ]
    rec <- data.frame(
      dataset = row$dataset, product = row$product,
      asset_id = ifelse(is.na(row$asset_id), NA_character_, row$asset_id),
      role = row$role, depth_basis = row$depth_basis, units = row$units_raw,
      pairs_with = ifelse(is.na(row$pairs_with), NA_character_, row$pairs_with),
      native_res_m = row$native_res_m, scale_used_m = NA_real_,
      mean = NA_real_, sd = NA_real_, min = NA_real_, max = NA_real_,
      coverage_frac = NA_real_, n_valid_px = NA_real_, n_total_px = NA_real_,
      mean_at_cores = NA_real_, n_cores_with_data = NA_integer_,
      status = NA_character_, note = row$note,
      stringsAsFactors = FALSE
    )

    if (identical(row$role, "no_asset")) {
      rec$status <- "no GEE asset - not summarized"
      out[[i]] <- rec
      next
    }

    if (verbose) message("  [", i, "/", nrow(registry), "] ", row$dataset)

    img <- prior_image(row, aoi_ee)
    if (is.null(img)) {
      rec$status <- paste0("unavailable: ", attr(img, "reason"))
      out[[i]] <- rec
      next
    }

    scale <- if (!is.null(scale_override)) scale_override else row$native_res_m
    if (is.na(scale)) scale <- 250
    rec$scale_used_m <- scale

    band <- tryCatch(img$bandNames()$getInfo()[[1]], error = function(e) NULL)
    if (is.null(band)) {
      rec$status <- "unavailable: could not read band names"
      out[[i]] <- rec
      next
    }
    img <- img$select(band)

    stats <- tryCatch(ee_region_stats(img, aoi_ee, scale),
                      error = function(e) structure(list(), reason = conditionMessage(e)))
    cov <- tryCatch(ee_coverage_fraction(img, aoi_ee, scale),
                    error = function(e) NULL)

    if (length(stats) == 0) {
      rec$status <- paste0("reduction failed: ", attr(stats, "reason"))
      out[[i]] <- rec
      next
    }

    pick <- function(suffix) {
      key <- grep(paste0(suffix, "$"), names(stats), value = TRUE)
      if (length(key) == 0 || is.null(stats[[key[1]]])) NA_real_ else as.numeric(stats[[key[1]]])
    }
    rec$mean <- pick("mean"); rec$sd  <- pick("stdDev")
    rec$min  <- pick("min");  rec$max <- pick("max")

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

    # A layer can return a mean while covering almost none of the AOI. Say so
    # here rather than letting a 3%-coverage mean look like a regional value.
    rec$status <- if (is.na(rec$coverage_frac)) {
      "summarized (coverage unknown)"
    } else if (rec$coverage_frac == 0) {
      "NA - no coverage over this AOI"
    } else if (rec$coverage_frac < 0.5) {
      sprintf("partial coverage (%.0f%% of AOI)", 100 * rec$coverage_frac)
    } else {
      sprintf("summarized (%.0f%% of AOI)", 100 * rec$coverage_frac)
    }

    if (!is.na(rec$coverage_frac) && rec$coverage_frac == 0) {
      rec$mean <- NA_real_; rec$sd <- NA_real_
      rec$min <- NA_real_;  rec$max <- NA_real_
    }

    out[[i]] <- rec
  }

  do.call(rbind, out)
}
