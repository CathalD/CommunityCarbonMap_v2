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

# Where the prior has no value, it must contribute NOTHING rather than wipe out
# the pixel. That is not a special case -- it is what the update already does
# when the prior's precision is zero:
#
#   sd = Inf  ->  1/Inf^2 = 0  ->  posterior = the evidence, exactly
#
# NA is treated the same way, because 1/NA^2 is NA and would otherwise
# propagate through and delete the result. The prior MEAN is zeroed only where
# it is missing, and only because it gets multiplied by a zero precision --
# setting the mean to 0 as an estimate would be a claim of no carbon, which is
# a different and wrong statement.
bayesian_update_normal <- function(prior_mean, prior_sd, evidence_mean, evidence_sd) {
  prior_precision    <- ifelse(is.na(prior_sd),    0, 1 / prior_sd^2)
  evidence_precision <- ifelse(is.na(evidence_sd), 0, 1 / evidence_sd^2)

  prior_mu    <- ifelse(is.na(prior_mean),    0, prior_mean)
  evidence_mu <- ifelse(is.na(evidence_mean), 0, evidence_mean)

  posterior_precision <- prior_precision + evidence_precision

  # Neither source has anything to say -> the posterior is undefined, not zero.
  posterior_variance <- ifelse(posterior_precision > 0,
                               1 / posterior_precision, NA_real_)
  posterior_mean <- ifelse(
    posterior_precision > 0,
    posterior_variance *
      (prior_mu * prior_precision + evidence_mu * evidence_precision),
    NA_real_
  )

  list(
    posterior_mean = posterior_mean,
    posterior_sd   = sqrt(posterior_variance)
  )
}
