# Step 12 -- Check the change of spatial support
#
# Question: our simple safeguard against over-interpreting the 10 m map.
#
# Aggregate the posterior back to the prior's resolution and compare. Not a
# requirement that they match -- a diagnostic. A large difference is a
# question ("why did the regional evidence move the estimate this much?"),
# not automatically a failure.

check_change_of_support <- function(posterior_mean_fine, prior_mean_coarse) {
  library(terra)

  posterior_aggregated <- resample(posterior_mean_fine, prior_mean_coarse, method = "average")
  diff <- posterior_aggregated - prior_mean_coarse

  list(
    posterior_aggregated = posterior_aggregated,
    difference      = diff,
    mean_difference = as.numeric(global(diff, "mean", na.rm = TRUE))
  )
}
