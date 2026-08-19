# Step 3 -- Extract prior and covariates
#
# Question: what did the prior predict at each ground observation, and what
# environmental conditions occurred there?
#
# Builds the modelling dataset: one row per plot, with the prior, its SD,
# and every covariate sampled at that exact point. `covariate_stack` should
# be a named SpatRaster (e.g. rast(list(ndvi = ..., elevation = ..., slope = ...)))
# so the extracted column names come out predictably.

extract_prior_covariates <- function(field, prior_mean, prior_sd, covariate_stack) {
  library(terra)

  field$prior    <- terra::extract(prior_mean, field)[, 2]
  field$prior_sd <- terra::extract(prior_sd, field)[, 2]

  # An uncertainty without an estimate describes nothing. Older exports of the
  # prior rasters could disagree about where they have data (the SD layer was
  # gap-filled everywhere, the mean only where a product exists), which gave
  # FS-04 prior = NaN with prior_sd = 18.74 -- and then any average of prior_sd
  # ran over more plots than the average of prior. Keep the two coherent.
  field$prior_sd[!is.finite(field$prior)] <- NA_real_

  cov_vals <- terra::extract(covariate_stack, field)[, -1, drop = FALSE]
  cbind(field, cov_vals)
}

# Replace `observed` with the DEPTH-HARMONIZED stock over `target`.
#
# Without this, `observed` comes from the workbook's per-core 0-30 cm total,
# which for a core that stopped short of 30 cm is a measured stock over a
# shorter column -- PM-01-A reaches 14.5 cm and PM-02-A 20.7 cm. Comparing
# those to a full 0-30 cm prior understates them, and no model can see that the
# comparison is uneven. Step 2 is the step that exists to fix this, so the
# modelling dataset uses its output.
#
# Two caveats are carried forward as columns rather than dropped, because for
# the partial cores part of `observed` is now MODELLED (step 2's exponential
# decay below the deepest measured layer), not measured:
#   coverage_frac       fraction of the target interval actually cored
#   extrapolated_kg_m2  carbon contributed by the decay curve, not by a sample
attach_harmonized_observed <- function(field, harmonized, target = c(0, 30)) {
  h <- as.data.frame(harmonized)
  h <- h[h$top >= target[1] & h$bottom <= target[2], , drop = FALSE]

  agg <- stats::aggregate(
    cbind(stock_total_kg_m2, extrapolated_kg_m2, covered_cm) ~ plot_id,
    data = h, FUN = sum, na.rm = TRUE
  )
  agg$coverage_frac <- agg$covered_cm / (target[2] - target[1])

  idx <- match(field$plot_id, agg$plot_id)
  if (anyNA(idx)) {
    warning("no harmonized value for: ",
            paste(field$plot_id[is.na(idx)], collapse = ", "),
            " -- their `observed` is left as supplied", call. = FALSE)
  }

  keep <- !is.na(idx)
  field$observed[keep]           <- agg$stock_total_kg_m2[idx[keep]]
  field$extrapolated_kg_m2       <- NA_real_
  field$extrapolated_kg_m2[keep] <- agg$extrapolated_kg_m2[idx[keep]]
  field$coverage_frac            <- NA_real_
  field$coverage_frac[keep]      <- agg$coverage_frac[idx[keep]]
  field$depth_basis              <- sprintf("%g-%g cm (harmonized)", target[1], target[2])

  field
}
