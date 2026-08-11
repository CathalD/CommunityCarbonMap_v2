# Step 8 -- Start simple: prior vs. regional RF
#
# Question: can a regional Random Forest predict the ground observations
# better than the prior?
#
# If the regional model isn't beating the prior, stop here and find out why
# -- don't move on to Bayesian updating with a model that isn't adding
# information.

compare_prior_vs_model <- function(prior_metrics, rf_metrics) {
  data.frame(
    model = c("Prior", "Regional RF"),
    rmse  = c(prior_metrics$rmse, rf_metrics$rmse),
    mae   = c(prior_metrics$mae,  rf_metrics$mae),
    bias  = c(prior_metrics$bias, rf_metrics$bias)
  )
}

# validate_rf_workflow() (step 7) returns a collect_metrics() tibble with
# .metric/mean columns, not a rmse/mae/bias list -- reshape it so it lines up
# with the prior_metrics list built in step 4.
metrics_to_list <- function(metrics_tbl) {
  value_col <- if ("mean" %in% names(metrics_tbl)) "mean" else ".estimate"
  metric_name <- ifelse(metrics_tbl$.metric == "msd", "bias", metrics_tbl$.metric)
  setNames(as.list(metrics_tbl[[value_col]]), metric_name)
}
