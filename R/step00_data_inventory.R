# Step 0 -- What do we know?
#
# Question: before any modelling, what information already exists, and what
# does each piece actually represent (estimate, uncertainty, spatial support)?
#
# This is deliberately just a data.frame -- the value of Step 0 is forcing
# every dataset into the same five columns before it enters the workflow,
# not the code that builds the table.

build_data_inventory <- function() {
  data.frame(
    dataset = c(
      "Prior carbon", "Prior uncertainty", "Ground cores",
      "Sentinel-2", "DEM", "Land cover"
    ),
    mean_estimate = c(
      150, NA, 165, NA, NA, NA
    ),
    uncertainty = c(
      30, 30, 20, NA, NA, NA
    ),
    data_type = c(
      "raster", "raster", "ground",
      "raster", "raster", "raster"
    ),
    spatial_support = c(
      "250 m", "250 m", "core",
      "10 m", "30 m", "10 m"
    ),
    stringsAsFactors = FALSE
  )
}
