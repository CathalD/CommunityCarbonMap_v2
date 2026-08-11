source("R/step07_validate_regional_workflow.R")

rf_workflow   <- readRDS("outputs/rf_workflow.rds")
training_data <- read.csv("outputs/prior_vs_observed.csv")

# NOTE: with a 5-20 plot proof-of-concept dataset, v = 5 folds means ~1-4
# held-out points per fold -- expect noisy CV metrics until more field data
# comes in. That's a real signal, not a bug in the script.
cv_metrics <- validate_rf_workflow(rf_workflow, training_data, v = 5)

write.csv(cv_metrics, "outputs/rf_cv_metrics.csv", row.names = FALSE)
saveRDS(cv_metrics, "outputs/rf_metrics.rds")
print(cv_metrics)
