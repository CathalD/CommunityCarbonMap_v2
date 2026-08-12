# Step 0 -- What do we know?
#
# Authenticate Earth Engine, ingest the AOI and the core locations, then build
# the three step-0 tables and fold them into the inventory:
#
#   outputs/prior_map_table.csv     what the carbon maps say over the AOI
#   outputs/covariate_table.csv     what covariates we have over the AOI
#   outputs/open_ground_table.csv   what other open ground data exists in it
#   outputs/aoi_ground_cores.csv    the open-data profiles inside the AOI
#   outputs/data_inventory.csv      the workshop's step-0 inventory
#
# Everything is clipped to the AOI before reduction. Set DOWNLOAD_STACK to TRUE
# to also export the GeoTIFFs that run_01 and run_03 read.

source("R/step00_gee_setup.R")
source("R/step00_prior_tables.R")
source("R/step00_covariates.R")
source("R/step00_ground_data.R")
source("R/step00_visualize.R")
source("R/step00_data_inventory.R")

DOWNLOAD_STACK <- FALSE   # TRUE also writes data/*.tif for run_01 / run_03
MAKE_FIGURES   <- FALSE   # TRUE writes outputs/figures/*.png (needs the tifs)

dir.create("outputs", showWarnings = FALSE)

# --- 0a. authenticate and ingest ------------------------------------------
gee_init()

aoi    <- load_aoi("data/aoi.geojson")
aoi_ee <- aoi_to_ee(aoi)
write_aoi_gpkg(aoi, "data/aoi.gpkg")   # run_01 and _targets.R read the .gpkg
message(sprintf("AOI: %.0f km2", aoi_area_km2(aoi)))

pts    <- load_core_points("data/community_soil_cores.csv")
pts_ee <- core_points_to_ee(pts)
message(sprintf("Core locations: %d", nrow(pts)))

registry <- read_prior_registry("data/prior_assets.csv")

# --- 0b. table 1: what the carbon maps say --------------------------------
message("\nTable 1 -- prior carbon maps")
priors <- prior_map_table(aoi_ee, pts_ee = pts_ee, registry = registry)
write.csv(priors, "outputs/prior_map_table.csv", row.names = FALSE)
print(priors[, c("dataset", "mean", "sd", "coverage_frac", "status")])

# --- 0c. table 2: what covariates we have ---------------------------------
message("\nTable 2 -- covariates")
cov_imgs <- covariate_images(aoi_ee)
covariates <- covariate_table(aoi_ee, pts_ee = pts_ee, imgs = cov_imgs)
write.csv(covariates, "outputs/covariate_table.csv", row.names = FALSE)
print(covariates[, c("covariate", "mean", "sd", "coverage_frac", "status")])

# --- 0d. table 3: what other open ground data exists ----------------------
message("\nTable 3 -- open ground data inside the AOI")
extracted <- extract_aoi_ground_cores(aoi_ee, registry)
ground <- open_ground_table(aoi_ee, registry, extracted = extracted)
write.csv(ground, "outputs/open_ground_table.csv", row.names = FALSE)
write.csv(extracted$points, "outputs/aoi_ground_cores.csv", row.names = FALSE)
print(ground[, c("dataset", "n_features_in_aoi", "mean", "sd", "status")])

# --- 0e. the community cores, and the point layer run_03 reads ------------
cores <- summarize_community_cores("data/community_soil_cores.csv")
message(sprintf(
  "\nCommunity cores: %d total, %d with full 0-30 cm coverage, mean %.3f kg C/m2 (SD %.3f)",
  cores$n_cores, cores$n_full_coverage, cores$mean_kg_m2, cores$sd_kg_m2
))
write_field_plots(cores, "data/field_plots.gpkg")

# First look at the data, clipped to the AOI.
print(plot_aoi_data(aoi, sf::st_read("data/field_plots.gpkg", quiet = TRUE)))

# --- 0f. the inventory ----------------------------------------------------
inventory <- build_data_inventory(
  priors = priors, covariates = covariates, ground = ground,
  cores = cores, aoi = aoi
)
write.csv(inventory, "outputs/data_inventory.csv", row.names = FALSE)
print(inventory[, c("dataset", "mean_estimate", "uncertainty", "data_type",
                    "spatial_support")])

# --- 0g. the stack, and a look at it --------------------------------------
stack <- build_aoi_stack(aoi_ee, imgs = cov_imgs)

if (DOWNLOAD_STACK) {
  written <- download_aoi_stack(stack, aoi_ee, dir = "data", scale = 30)
  message("wrote: ", paste(written, collapse = ", "))
  if (MAKE_FIGURES) {
    pngs <- plot_stack_to_png(written, aoi = aoi, pts = pts)
    message("figures: ", paste(pngs, collapse = ", "))
  }
}

# Interactive look, clipped to the AOI. Run this line in the console rather than
# via Rscript -- it opens a browser map.
# view_aoi_stack(stack, aoi_ee, pts_ee = pts_ee, aoi_sf = aoi)
