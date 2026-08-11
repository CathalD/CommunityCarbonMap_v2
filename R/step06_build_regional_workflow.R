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
# mtry/min_n are left at ranger's defaults (NULL) rather than tune() on
# purpose: tuning needs tune_grid() + finalize_workflow() before the
# workflow can be fit, which is more machinery than a 5-20 plot proof of
# concept needs. Pass explicit values, or wire up tune_grid() yourself,
# once there's enough data for tuning to be worth it.

build_rf_workflow <- function(formula, data, trees = 500, mtry = NULL, min_n = NULL) {
  library(tidymodels)

  rf_model <- rand_forest(trees = trees, mtry = mtry, min_n = min_n) |>
    set_mode("regression") |>
    set_engine("ranger")

  rf_recipe <- recipe(formula, data = data)

  workflow() |>
    add_recipe(rf_recipe) |>
    add_model(rf_model)
}
