# Step 4 -- Prior vs. observed
#
# Question: how well does the existing prior agree with our regional field
# observations?
#
# Base R is preferable to a package here -- the calculation is this simple.

compare_prior_observed <- function(field) {
  field$residual   <- field$observed - field$prior
  field$z_residual <- field$residual / field$prior_sd

  list(
    field = field,
    bias  = mean(field$residual),
    mae   = mean(abs(field$residual)),
    rmse  = sqrt(mean(field$residual^2))
  )
}
