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

  n <- nrow(data)

  # With 8 plots and v = 5, assessment sets hold 1-2 observations. rsq needs
  # variance in the held-out set, so it is undefined on a single point and the
  # whole resample fails ("All models failed"). Cap v so each fold keeps at
  # least two observations, and only ask for rsq when there are enough to
  # compute it.
  v <- max(2L, min(as.integer(v), floor(n / 2)))
  per_fold <- floor(n / v)

  # msd = mean signed deviation, i.e. bias -- kept alongside rmse/mae so this
  # lines up with the prior's bias/mae/rmse from step 4 (see step 8's
  # metrics_to_list()).
  metrics <- if (per_fold >= 3) {
    metric_set(rmse, mae, rsq, msd)
  } else {
    message("n = ", n, ": ", per_fold, " observations per fold, so rsq is ",
            "not estimable and is omitted.")
    metric_set(rmse, mae, msd)
  }

  folds <- vfold_cv(data, v = v)

  results <- workflow |>
    fit_resamples(resamples = folds, metrics = metrics)

  collect_metrics(results)
}
