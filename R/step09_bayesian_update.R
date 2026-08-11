# Step 9 -- Bayesian update
#
# Question: given what we knew before and what the regional evidence tells
# us, what should our updated estimate be?
#
# The first genuinely Bayesian step. Version 1 uses the Normal-Normal update:
# precision-weighted averaging of a prior and a piece of evidence, each
# described by a mean and an SD.
#
# Worked example: prior 150 +/- 30, regional evidence 170 +/- 20
#   -> posterior ~= 164 +/- 17

bayesian_update_normal <- function(prior_mean, prior_sd, evidence_mean, evidence_sd) {
  prior_precision     <- 1 / prior_sd^2
  evidence_precision  <- 1 / evidence_sd^2
  posterior_precision <- prior_precision + evidence_precision
  posterior_variance  <- 1 / posterior_precision

  posterior_mean <- posterior_variance *
    (prior_mean * prior_precision + evidence_mean * evidence_precision)

  list(
    posterior_mean = posterior_mean,
    posterior_sd   = sqrt(posterior_variance)
  )
}
