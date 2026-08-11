# Step 7 -- Validate the model
#
# Question: how does the model perform on observations it hasn't seen?
#
# Version 1 uses ordinary v-fold cross-validation -- treating folds as
# independent is a simplification made on purpose. Once this baseline works,
# `spatialsample` extends tidymodels with spatially-structured resampling,
# which better respects that nearby ecological observations aren't
# independent.

validate_rf_workflow <- function(workflow, data, v = 5, seed = 123) {
  library(tidymodels)
  set.seed(seed)

  folds   <- vfold_cv(data, v = v)
  # msd = mean signed deviation, i.e. bias -- kept alongside rmse/mae/rsq so
  # this lines up with the prior's bias/mae/rmse from step 4 (see step 8's
  # metrics_to_list()).
  metrics <- metric_set(rmse, mae, rsq, msd)

  results <- workflow |>
    fit_resamples(resamples = folds, metrics = metrics)

  collect_metrics(results)
}
