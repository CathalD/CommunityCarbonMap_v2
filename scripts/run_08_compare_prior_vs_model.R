source("R/step08_compare_prior_vs_model.R")

prior_metrics <- readRDS("outputs/prior_metrics.rds")  # from run_04
rf_cv         <- readRDS("outputs/rf_metrics.rds")      # from run_07 (collect_metrics tibble)
rf_metrics    <- metrics_to_list(rf_cv)

comparison_table <- compare_prior_vs_model(prior_metrics, rf_metrics)
write.csv(comparison_table, "outputs/prior_vs_rf_comparison.csv", row.names = FALSE)
print(comparison_table)

# Stop and investigate here if the regional RF does not beat the prior --
# don't move on to run_09_bayesian_update.R with a model that isn't adding
# information.
