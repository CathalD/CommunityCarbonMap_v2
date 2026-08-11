source("R/step06_build_regional_workflow.R")

training_data <- read.csv("outputs/prior_vs_observed.csv")

rf_workflow <- build_rf_workflow(
  observed ~ ndvi + elevation + slope + prior,
  training_data
)

saveRDS(rf_workflow, "outputs/rf_workflow.rds")
rf_workflow
