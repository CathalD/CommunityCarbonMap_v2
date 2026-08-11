# Step 13 -- Compare the maps
#
# Question: what did we gain?
#
#   A. delta_mu = posterior_mean - prior_mean       -- where did the estimate change?
#   B. 1 - (posterior_sd / prior_sd)                -- where did uncertainty decrease?
#
# Worked example: SD_prior = 30, SD_post = 16.6 -> uncertainty reduction = 44.7%

compare_prior_posterior_maps <- function(prior_mean, posterior_mean, prior_sd, posterior_sd) {
  delta_mu <- posterior_mean - prior_mean
  uncertainty_reduction <- 1 - (posterior_sd / prior_sd)

  out <- c(delta_mu, uncertainty_reduction)
  names(out) <- c("delta_mu", "uncertainty_reduction")
  out
}
