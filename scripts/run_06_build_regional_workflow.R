source("R/step06_build_regional_workflow.R")

training_data <- read.csv("outputs/prior_vs_observed.csv")

# `prior` is deliberately NOT a predictor. It is the prior in the Normal-Normal
# update at steps 9-10, and that update assumes the prior and the evidence are
# independent sources of information. Using it here as well puts the prior
# inside the evidence, so its precision gets added twice and the posterior SD
# comes out too small. Sharing COVARIATES with the large-scale model is fine --
# it is reusing the prior's own output that breaks the independence assumption.
rf_workflow <- build_rf_workflow(
  observed ~ ndvi + elevation + slope,
  training_data
)

saveRDS(rf_workflow, "outputs/rf_workflow.rds")
rf_workflow
