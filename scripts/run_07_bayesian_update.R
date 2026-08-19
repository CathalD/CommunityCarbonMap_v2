source("R/step07_bayesian_update.R")

posterior <- bayesian_update_normal(
  prior_mean = 150, prior_sd = 30,
  evidence_mean = 170, evidence_sd = 20
)
print(posterior)

# check against the worked example: 164 +/- 17
stopifnot(round(posterior$posterior_mean) == 164)
stopifnot(round(posterior$posterior_sd)   == 17)
