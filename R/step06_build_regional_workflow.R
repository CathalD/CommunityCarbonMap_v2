# Step 6 -- Build the regional model
#
# Question: can high-resolution environmental information explain the
# ground observations?
#
# Standardized on tidymodels (workflow/validation) + ranger (Random Forest
# engine) instead of independently wiring up caret, ranger, and ad-hoc
# validation code. Returns an untrained workflow -- fitting happens in
# step 7 (fit_resamples) and the bridge script (fit() on all the data).
#
# mtry/min_n are left at ranger's defaults rather than tune() on purpose:
# tuning needs tune_grid() + finalize_workflow() before the workflow can be
# fit, which is more machinery than a 5-20 plot proof of concept needs. Pass
# explicit values, or wire up tune_grid() yourself, once there's enough data
# for tuning to be worth it.
#
# They must be OMITTED, not passed as NULL. parsnip treats an explicit NULL as
# "this argument was supplied" and rewrites it for the ranger engine as
# min_cols(NULL, x); inside min_cols() that becomes `NULL > p`, i.e. logical(0),
# and the fit dies with "argument is of length zero" for every resample.

build_rf_workflow <- function(formula, data, trees = 500, mtry = NULL, min_n = NULL) {
  library(tidymodels)

  args <- list(trees = trees)
  if (!is.null(mtry))  args$mtry  <- mtry
  if (!is.null(min_n)) args$min_n <- min_n

  rf_model <- do.call(rand_forest, args) |>
    set_mode("regression") |>
    set_engine("ranger")

  rf_recipe <- recipe(formula, data = data)

  workflow() |>
    add_recipe(rf_recipe) |>
    add_model(rf_model)
}
