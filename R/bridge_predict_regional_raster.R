# Bridge: fitted regional model (steps 6-7) -> spatial prediction rasters
#
# Not one of the framework's numbered steps -- it is the plumbing between
# "build/validate the regional model" (steps 6-7) and "apply the Bayesian
# update spatially" (step 10): turning a fitted tabular model into the
# regional_mean / regional_sd rasters step 10 expects.
#
# Version 1 keeps regional uncertainty simple on purpose: every pixel gets
# the SAME regional_sd, taken from the model's cross-validated RMSE
# (step 7). That is the same honest simplification step 1 makes for the
# prior's pixel SD -- one defensible number, not a claim about per-pixel
# model confidence. A genuine per-pixel regional SD (a ranger quantile-
# regression forest, or the step 14 spatial Bayesian model) is a Version 2
# upgrade, not a Version 1 requirement.
#
# `covariate_stack` must carry a band for every predictor in the model
# formula, spelled exactly the same way -- including "prior" if the prior
# is one of the predictors (see scripts/run_08b_predict_regional_raster.R).

predict_regional_raster <- function(workflow, training_data, covariate_stack, cv_rmse) {
  library(terra)
  library(tidymodels)

  fitted_model <- fit(workflow, data = training_data)

  covariate_df <- as.data.frame(covariate_stack, xy = TRUE, na.rm = FALSE)
  covariate_df$.pred <- predict(fitted_model, new_data = covariate_df)$.pred

  regional_mean <- rast(
    covariate_df[, c("x", "y", ".pred")],
    type = "xyz", crs = crs(covariate_stack)
  )
  names(regional_mean) <- "regional_mean"

  regional_sd <- regional_mean
  values(regional_sd) <- cv_rmse
  names(regional_sd) <- "regional_sd"

  c(regional_mean, regional_sd)
}
