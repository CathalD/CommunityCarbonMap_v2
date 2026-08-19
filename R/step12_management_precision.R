# Step 15 -- Management precision
#
# Question: not "is the model statistically perfect?" -- "is the map good
# enough for the management decision?"
#
# CV_post = SD_post / mu_post. Worked example: 16.6 / 164 = 10.1%, which
# passes a 20% management threshold.
#
# (There is no step 14 script -- step 14 is a roadmap marker for a future
# hierarchical spatial Bayesian model, not a task with code attached.)

test_management_precision <- function(posterior_mean, posterior_sd, cv_threshold = 0.20) {
  cv <- posterior_sd / posterior_mean
  list(
    cv     = cv,
    passes = cv < cv_threshold
  )
}
