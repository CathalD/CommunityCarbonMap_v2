source("R/step11_export_posterior.R")
library(terra)

posterior <- rast("outputs/posterior_10m.tif")
export_posterior_products(
  posterior[["posterior_mean"]], posterior[["posterior_sd"]], "outputs/posterior"
)
