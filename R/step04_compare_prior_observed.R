# Step 4 -- Prior vs. observed
#
# Question: how well does the existing prior agree with our regional field
# observations?
#
# Base R is preferable to a package here -- the calculation is this simple.

# Plots where the prior is NoData give a NA residual. That is not a bug to hide
# with na.rm -- a peat-only prior has no value over mineral ground, so those
# plots carry no information about how well the prior performs. They are counted
# and reported, and the metrics are computed on the rest.
compare_prior_observed <- function(field) {
  field$residual   <- field$observed - field$prior
  field$z_residual <- field$residual / field$prior_sd

  r <- field$residual
  ok <- is.finite(r)

  if (!any(ok)) {
    warning("no plot has both an observation and a prior value -- ",
            "the prior does not cover any of the field plots", call. = FALSE)
  } else if (any(!ok)) {
    warning(sum(!ok), " of ", length(ok), " plots have no prior value ",
            "(NoData) and are excluded from bias/MAE/RMSE", call. = FALSE)
  }

  list(
    field       = field,
    n_used      = sum(ok),
    n_no_prior  = sum(!ok),
    bias        = if (any(ok)) mean(r[ok])             else NA_real_,
    mae         = if (any(ok)) mean(abs(r[ok]))        else NA_real_,
    rmse        = if (any(ok)) sqrt(mean(r[ok]^2))     else NA_real_
  )
}
