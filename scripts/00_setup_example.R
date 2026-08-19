# Set up the workshop EXAMPLE so the whole pipeline runs on fictional data.
#
# Copies the example AOI into place and writes the two analysis inputs directly
# from data/example_soil_cores.csv, so you can run the pipeline end to end
# before you have any field data of your own:
#
#   data/aoi.geojson       <- data/example_aoi.geojson   (backs up any existing)
#   data/soil_cores_raw.csv    the layer table step 2 reads
#   data/field_plots.gpkg      the core locations step 3 reads
#
# The field WORKBOOK route (fill in soil_carbon_calculation.xlsx, export the
# sheets, run run_00b) produces exactly the same two files -- that is the route
# your own data takes, and the workbook ships pre-filled with this same example
# so you can compare. This script is just the shortcut past the spreadsheet.

d <- read.csv("data/example_soil_cores.csv", check.names = FALSE,
              stringsAsFactors = FALSE)

# --- AOI --------------------------------------------------------------------
if (file.exists("data/aoi.geojson") &&
    !identical(readLines("data/aoi.geojson", warn = FALSE),
               readLines("data/example_aoi.geojson", warn = FALSE))) {
  file.copy("data/aoi.geojson", "data/aoi_backup.geojson", overwrite = TRUE)
  message("existing data/aoi.geojson backed up to data/aoi_backup.geojson")
}
file.copy("data/example_aoi.geojson", "data/aoi.geojson", overwrite = TRUE)

# --- layer table for step 2 -------------------------------------------------
# depth_from/depth_to stacked from the surface (the csv's Depth column is each
# slice's THICKNESS); soc in g/kg = % x 10, the unit step 2 expects.
top <- ave(d$Depth, d$`Core Id`, FUN = function(x) cumsum(x) - x)
write.csv(
  data.frame(
    plot_id      = d$`Core Id`,
    depth_from   = top,
    depth_to     = top + d$Depth,
    soc          = d$SOC * 10,
    bulk_density = d$`Bulk Density`,
    coarse_frag  = 0
  ),
  "data/soil_cores_raw.csv", row.names = FALSE
)

# --- core locations for step 3 ----------------------------------------------
library(sf)
first <- !duplicated(d$`Core Id`)
q <- d$`Bulk Density` * d$SOC / 100
ov <- pmax(0, pmin(top + d$Depth, 30) - pmax(top, 0))
stock030 <- tapply(q * ov * 10, d$`Core Id`, sum)

pts <- st_as_sf(
  data.frame(
    plot_id   = d$`Core Id`[first],
    observed  = as.numeric(stock030[d$`Core Id`[first]]),
    year      = d$year[first],
    longitude = d$Longitude[first],
    latitude  = d$Latitude[first]
  ),
  coords = c("longitude", "latitude"), crs = 4326, remove = FALSE
)
st_write(pts, "data/field_plots.gpkg", delete_dsn = TRUE, quiet = TRUE)

message(sprintf(
  "example ready: %d cores (%d from 2023, %d from 2024), 0-30 cm mean %.1f sd %.1f kg C/m2",
  nrow(pts), sum(pts$year == 2023), sum(pts$year == 2024),
  mean(pts$observed), sd(pts$observed)
))
message("next: scripts/run_00_data_inventory.R (downloads priors/covariates for this AOI)")
