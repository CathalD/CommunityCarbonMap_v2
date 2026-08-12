# Step 0, TABLE 3 -- what other open ground data already exists inside our AOI.
#
# Two outputs, because "what exists" and "what is usable here" are different
# questions:
#   open_ground_table()      one row per point database: how many profiles it
#                            holds in total, how many fall inside the AOI, and
#                            the mean/sd/source of those that do.
#   extract_aoi_ground_cores() the profiles themselves, pulled out into one
#                            table so they can sit beside the community cores.
#
# The spreadsheet already warns what to expect: zero NPDB mineral pedons fall in
# the Hudson & James Bay Lowlands, and the global WOSIS component is 92% United
# States. An empty result here is a finding, not a failure.

source_once_gnd <- function(path) if (!exists("gee_init")) source(path)
source_once_gnd("R/step00_gee_setup.R")

# Carbon-ish property names seen across WoSIS / CanPeat / the combined asset.
# The first one present on the asset wins; if none match, the property names
# actually found get reported so the right one can be passed in explicitly.
GROUND_VALUE_CANDIDATES <- c(
  "stock_0_30cm", "stock_0_30", "ocs_0_30", "ocs_0_30cm",
  "soc_stock", "carbon_kg_m2", "kg_m2", "ocs",
  "orgc_value_avg", "soc", "carbon"
)

pick_value_field <- function(props, candidates = GROUND_VALUE_CANDIDATES) {
  hit <- candidates[candidates %in% props]
  if (length(hit)) hit[1] else NA_character_
}

#' Pull every open-data profile that falls inside the AOI into one table.
#'
#' @param registry data.frame from read_prior_registry(); rows with
#'   asset_type == "table" are the point databases.
#' @param value_fields optional named vector, dataset -> property to summarize,
#'   overriding the automatic pick.
#' @param max_features refuse to pull more than this many features client-side;
#'   above it, the collection needs a proper export instead.
extract_aoi_ground_cores <- function(aoi_ee,
                                     registry,
                                     value_fields = NULL,
                                     max_features = 5000,
                                     verbose = TRUE) {
  library(rgee)
  library(sf)

  reg <- registry[registry$asset_type %in% "table", , drop = FALSE]
  points <- list()
  meta <- list()

  for (i in seq_len(nrow(reg))) {
    row <- reg[i, ]
    if (verbose) message("  [", i, "/", nrow(reg), "] ", row$dataset)

    m <- data.frame(
      dataset = row$dataset, product = row$product, asset_id = row$asset_id,
      n_features_total = NA_real_, n_features_in_aoi = NA_real_,
      value_field = NA_character_, mean = NA_real_, sd = NA_real_,
      units = NA_character_, depth_basis = row$depth_basis,
      source = row$product, status = NA_character_, note = row$note,
      stringsAsFactors = FALSE
    )

    info <- tryCatch(ee$data$getAsset(row$asset_id), error = function(e) NULL)
    if (is.null(info)) {
      m$status <- "unavailable: asset not found or not readable by this account"
      meta[[i]] <- m
      next
    }

    fc_all <- ee$FeatureCollection(row$asset_id)
    m$n_features_total <- tryCatch(as.numeric(fc_all$size()$getInfo()),
                                   error = function(e) NA_real_)

    fc <- fc_all$filterBounds(aoi_ee)
    n_in <- tryCatch(as.numeric(fc$size()$getInfo()), error = function(e) NA_real_)
    m$n_features_in_aoi <- n_in

    if (is.na(n_in)) {
      m$status <- "filterBounds failed"
      meta[[i]] <- m
      next
    }
    if (n_in == 0) {
      m$status <- "NA - no profiles inside this AOI"
      meta[[i]] <- m
      next
    }
    if (n_in > max_features) {
      m$status <- sprintf(
        "%.0f features in AOI exceeds max_features (%d) - export this one instead",
        n_in, max_features
      )
      meta[[i]] <- m
      next
    }

    props <- tryCatch(sort(unlist(fc$first()$propertyNames()$getInfo())),
                      error = function(e) character(0))
    vf <- if (!is.null(value_fields) && row$dataset %in% names(value_fields)) {
      value_fields[[row$dataset]]
    } else {
      pick_value_field(props)
    }

    got <- tryCatch(rgee::ee_as_sf(fc), error = function(e) NULL)
    if (is.null(got)) {
      m$status <- "could not pull features client-side"
      meta[[i]] <- m
      next
    }

    coords <- tryCatch(sf::st_coordinates(sf::st_centroid(sf::st_geometry(got))),
                       error = function(e) NULL)
    df <- data.frame(
      dataset    = row$dataset,
      feature_id = if ("id" %in% names(got)) as.character(got$id) else as.character(seq_len(nrow(got))),
      longitude  = if (is.null(coords)) NA_real_ else coords[, 1],
      latitude   = if (is.null(coords)) NA_real_ else coords[, 2],
      value      = NA_real_,
      value_field = vf,
      source     = row$product,
      stringsAsFactors = FALSE
    )

    if (is.na(vf)) {
      m$value_field <- NA_character_
      m$status <- paste0(
        "profiles found but no recognised carbon field. Properties available: ",
        paste(props, collapse = ", "),
        " -- pass value_fields = c('", row$dataset, "' = '<field>')"
      )
    } else {
      df$value <- suppressWarnings(as.numeric(sf::st_drop_geometry(got)[[vf]]))
      keep <- !is.na(df$value)
      m$value_field <- vf
      m$mean <- if (any(keep)) mean(df$value[keep]) else NA_real_
      m$sd   <- if (sum(keep) > 1) stats::sd(df$value[keep]) else NA_real_
      m$units <- "see source asset - not declared in the catalogue"
      m$status <- sprintf("%.0f profiles in AOI, %d with a value in '%s'",
                          n_in, sum(keep), vf)
    }

    points[[length(points) + 1]] <- df
    meta[[i]] <- m
  }

  list(
    points  = if (length(points)) do.call(rbind, points) else
      data.frame(dataset = character(0), feature_id = character(0),
                 longitude = numeric(0), latitude = numeric(0),
                 value = numeric(0), value_field = character(0),
                 source = character(0), stringsAsFactors = FALSE),
    summary = do.call(rbind, meta)
  )
}

#' Table 3 -- open ground data available for this AOI.
#'
#' The point databases that were actually queried, plus every ground dataset in
#' the catalogue that has no Earth Engine asset, carried as an explicit NA row.
open_ground_table <- function(aoi_ee,
                              registry,
                              extracted = NULL,
                              value_fields = NULL,
                              verbose = TRUE) {
  if (is.null(extracted)) {
    extracted <- extract_aoi_ground_cores(aoi_ee, registry,
                                          value_fields = value_fields,
                                          verbose = verbose)
  }

  queried <- extracted$summary

  # Ground datasets in the catalogue with no asset to query -- named here so
  # they are visibly NA rather than silently absent.
  no_asset_ground <- c("npdb_aafc", "canpeat_synthesis", "ogs_riley",
                       "janousek_tidal")
  na_rows <- registry[registry$dataset %in% no_asset_ground, , drop = FALSE]

  if (nrow(na_rows)) {
    na_tab <- data.frame(
      dataset = na_rows$dataset, product = na_rows$product,
      asset_id = NA_character_,
      n_features_total = NA_real_, n_features_in_aoi = NA_real_,
      value_field = NA_character_, mean = NA_real_, sd = NA_real_,
      units = NA_character_, depth_basis = na_rows$depth_basis,
      source = na_rows$product,
      status = "no GEE asset - not queried",
      note = na_rows$note,
      stringsAsFactors = FALSE
    )
    queried <- rbind(queried, na_tab)
  }

  queried
}

#' The community cores, summarized the same way the workbook does.
#'
#' Reproduces sheets 3-4 of data/soil_carbon_calculation.xlsx in R. If these
#' numbers and the spreadsheet ever disagree, the spreadsheet is right and this
#' function is wrong -- that is the workshop's rule, and the reason this is
#' written out longhand rather than read from the xlsx.
summarize_community_cores <- function(path = "data/community_soil_cores.csv",
                                      target = c(0, 30)) {
  d <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)

  core_id   <- d[["Core Id"]]
  thickness <- as.numeric(d[["Depth"]])
  bulk_den  <- as.numeric(d[["Bulk Density"]])
  soc_pct   <- as.numeric(d[["SOC"]])

  # "Depth" is slice THICKNESS, so stack the slices from the surface per core.
  depth_to   <- stats::ave(thickness, core_id, FUN = cumsum)
  depth_from <- depth_to - thickness

  c_density <- bulk_den * soc_pct / 100                       # g C/cm3
  overlap <- pmax(0, pmin(depth_to, target[2]) - pmax(depth_from, target[1]))
  stock <- c_density * overlap * 10                           # kg C/m2

  per_core <- data.frame(
    core_id = core_id, stock = stock, thickness = thickness,
    stringsAsFactors = FALSE
  )
  agg <- stats::aggregate(cbind(stock, thickness) ~ core_id, data = per_core, FUN = sum)
  names(agg)[names(agg) == "thickness"] <- "core_bottom_cm"
  names(agg)[names(agg) == "stock"] <- "stock_kg_m2"

  first <- !duplicated(core_id)
  loc <- data.frame(
    core_id   = core_id[first],
    year      = d[["year"]][first],
    latitude  = as.numeric(d[["Latitude"]][first]),
    longitude = -abs(as.numeric(d[["Longitude"]][first])),
    stringsAsFactors = FALSE
  )
  agg <- merge(loc, agg, by = "core_id")
  agg$full_coverage <- agg$core_bottom_cm >= target[2]

  full <- agg[agg$full_coverage, ]
  list(
    per_core = agg,
    n_cores = nrow(agg),
    n_full_coverage = nrow(full),
    mean_kg_m2 = if (nrow(full)) mean(full$stock_kg_m2) else NA_real_,
    sd_kg_m2   = if (nrow(full) > 1) stats::sd(full$stock_kg_m2) else NA_real_,
    depth_basis = sprintf("%g-%g cm", target[1], target[2])
  )
}

#' Write the point layer run_03 reads, from the community cores.
#'
#' Closes the gap between step 0 and step 3: field_plots.gpkg needs plot_id and
#' observed, and observed is the 0-30 cm stock computed above. Every core is
#' written -- depth harmonization (step 2) is what reconciles cores of different
#' lengths, so filtering here would pre-empt it. core_bottom_cm rides along.
write_field_plots <- function(cores = summarize_community_cores(),
                              dsn = "data/field_plots.gpkg",
                              full_coverage_only = FALSE) {
  library(sf)
  d <- cores$per_core
  if (full_coverage_only) d <- d[d$full_coverage, ]

  pts <- sf::st_as_sf(
    data.frame(
      plot_id  = d$core_id,
      observed = d$stock_kg_m2,
      year     = d$year,
      core_bottom_cm = d$core_bottom_cm,
      longitude = d$longitude,
      latitude  = d$latitude,
      stringsAsFactors = FALSE
    ),
    coords = c("longitude", "latitude"), crs = 4326, remove = FALSE
  )

  sf::st_write(pts, dsn, delete_dsn = TRUE, quiet = TRUE)
  dsn
}
