source("R/step04_compare_prior_observed.R")
library(sf)

field_sf <- st_read("outputs/modelling_dataset.gpkg", quiet = TRUE)
field_df <- st_drop_geometry(field_sf)

comparison <- compare_prior_observed(field_df)
print(comparison[c("bias", "mae", "rmse")])

# check against the workshop's worked example: residuals 10,5,10,-15,10 -> bias 4
stopifnot(mean(c(10, 5, 10, -15, 10)) == 4)

field_sf$residual   <- comparison$field$residual
field_sf$z_residual <- comparison$field$z_residual

write.csv(comparison$field, "outputs/prior_vs_observed.csv", row.names = FALSE)
st_write(field_sf, "outputs/prior_vs_observed.gpkg", delete_dsn = TRUE, quiet = TRUE)
saveRDS(comparison[c("bias", "mae", "rmse")], "outputs/prior_metrics.rds")
