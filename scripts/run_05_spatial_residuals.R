source("R/step05_spatial_residuals.R")
library(sf)

field_sf    <- st_read("outputs/prior_vs_observed.gpkg", quiet = TRUE)
diagnostics <- spatial_residual_diagnostics(field_sf, run_moran = TRUE)

ggplot2::ggsave("outputs/residual_map.png", diagnostics$plot, width = 7, height = 5)
print(diagnostics$moran)
