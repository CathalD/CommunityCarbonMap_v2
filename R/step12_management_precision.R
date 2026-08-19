# Step 12 -- Is the estimate (or the map) good enough to manage by?
#
# The question is never "is the model perfect?" -- it is "does the estimate
# meet the precision target the USER set before sampling?" Both halves of that
# target are theirs to choose:
#
#   margin      the acceptable margin of error, as a fraction of the estimate
#               (0.20 = "within +/- 20% of the mean")
#   confidence  how sure they want to be that the truth is inside that margin
#               (0.80 = "80% confident"; 0.95 is the other common choice)
#
# The test: margin of error = z x SD, where z comes from the confidence level
# (qnorm() in base R turns a confidence level into its z value: 0.80 -> 1.282,
# 0.95 -> 1.960). Pass if z x SD <= margin x mean.
#
# Works on single numbers (a Tier 0 estimate) and on rasters (a posterior map,
# tested pixel by pixel) with the same arithmetic -- terra overloads +, *, <=
# for SpatRasters, so the one formula serves both.

test_management_precision <- function(estimate_mean, estimate_sd,
                                      margin = 0.20, confidence = 0.80) {
  z <- stats::qnorm(1 - (1 - confidence) / 2)   # two-sided
  moe <- z * estimate_sd

  if (inherits(estimate_mean, "SpatRaster")) {
    # a zero or negative mean has no meaningful relative margin -- report NA
    # there rather than letting the comparison silently pass or fail
    ok <- terra::ifel(estimate_mean > 0, moe <= margin * estimate_mean, NA)
    rel <- terra::ifel(estimate_mean > 0, moe / estimate_mean, NA)
  } else {
    ok  <- ifelse(estimate_mean > 0, moe <= margin * estimate_mean, NA)
    rel <- ifelse(estimate_mean > 0, moe / estimate_mean, NA)
  }

  list(
    z               = z,
    margin_of_error = moe,     # absolute, same units as the estimate
    relative_moe    = rel,     # fraction of the mean -- compare to `margin`
    passes          = ok,
    target          = sprintf("+/-%.0f%% at %.0f%% confidence",
                              100 * margin, 100 * confidence)
  )
}

#' How many cores would it take to hit the target?
#'
#' Plans next season. Given the cores' spread (their SD, not SE) and the
#' target, returns the sample size needed -- with no prior (the frequentist
#' answer) and with the prior helping (the Bayesian answer). The prior-assisted
#' number assumes the prior is trustworthy and unbiased; if step 6's
#' calibration says otherwise, use the frequentist number.
cores_needed_for_target <- function(expected_mean, core_sd,
                                    prior_sd = NULL,
                                    margin = 0.20, confidence = 0.80) {
  z <- stats::qnorm(1 - (1 - confidence) / 2)
  se_target <- margin * expected_mean / z         # the SE that just passes

  n_freq <- ceiling((core_sd / se_target)^2)

  n_bayes <- NA_integer_
  if (!is.null(prior_sd) && is.finite(prior_sd) && prior_sd > 0) {
    # the evidence only needs to supply the precision the prior doesn't
    need <- 1 / se_target^2 - 1 / prior_sd^2
    n_bayes <- if (need <= 0) 0L else ceiling(core_sd^2 * need)
  }

  list(se_target = se_target, n_frequentist = n_freq, n_with_prior = n_bayes,
       target = sprintf("+/-%.0f%% at %.0f%% confidence",
                        100 * margin, 100 * confidence))
}
