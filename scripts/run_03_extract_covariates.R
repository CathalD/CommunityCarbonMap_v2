source("R/step03_extract_covariates.R")
library(terra)

# field_plots.gpkg already carries prior/covariate columns from the
# synthetic-data generator -- keep only plot_id + observed here so the
# extraction function below is doing real work, not repeating it.
field_raw <- vect("data/field_plots.gpkg")[, c("plot_id", "observed")]

prior_mean <- rast("data/prior_mean_10m.tif")
prior_sd   <- rast("data/prior_sd_10m.tif")

# covariates are on different native grids (10 m NDVI, 30 m DEM/slope) --
# resample everything onto the NDVI grid before stacking so terra::c() has
# matching geometry to work with.
ndvi  <- rast("data/sentinel2_ndvi.tif")
dem   <- resample(rast("data/dem.tif"),   ndvi, method = "bilinear")
slope <- resample(rast("data/slope.tif"), ndvi, method = "bilinear")
covariates <- c(ndvi, dem, slope)

modelling_data <- extract_prior_covariates(field_raw, prior_mean, prior_sd, covariates)

dir.create("outputs", showWarnings = FALSE)
writeVector(modelling_data, "outputs/modelling_dataset.gpkg", overwrite = TRUE)
write.csv(as.data.frame(modelling_data), "outputs/modelling_dataset.csv", row.names = FALSE)
head(as.data.frame(modelling_data))
