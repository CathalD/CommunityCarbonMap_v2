# Step 14 -- run the model tier ladder.
#
# Replaces run_06 / run_07 / run_08 (the Random Forest path). An RF on a
# handful of plots memorises them; the ladder starts from a model the data can
# actually carry and only climbs when the data allows.
#
# What runs by default: the decision aid, Tier 0, Tier 1, and the
# prior-evidence correlation. That is deliberate -- see FIT_BAYES below.

source("R/step07_bayesian_update.R")   # Tier 0 reuses bayesian_update_normal()
source("R/step12_management_precision.R")  # the precision test + sample-size aid
source("R/step06_tier_ladder.R")
source("R/step06_fit_bayes.R")
source("R/step06_evaluate.R")

# Tiers 2-4 need Stan and are only worth fitting once the sample size supports
# them. Flip this on deliberately; tier_recommendation() below tells you
# whether that is justified yet.
FIT_BAYES  <- FALSE
COVARIATES <- c("ndvi", "elevation", "slope")

# Your precision target -- both numbers are yours to set (see the workshop's
# "good enough to manage by" section). The resolution of any map you build is
# set separately, in build_prediction_grid(cellsize = ...).
TARGET_MARGIN     <- 0.20   # +/- 20% of the estimate
TARGET_CONFIDENCE <- 0.80   # at 80% confidence

dir.create("outputs", showWarnings = FALSE)

# --- data -------------------------------------------------------------------
# `observed` here is the DEPTH-HARMONIZED stock (step 3 attaches it from step
# 2), not the workbook per-core total.
# Read WITH geometry: the spatial tiers need coordinates, and
# as.data.frame() on a SpatVector drops them.
md <- add_projected_coords(terra::vect("outputs/modelling_dataset.gpkg"))

usable <- md[is.finite(md$observed), , drop = FALSE]
message("\nCores with a harmonized value: ", nrow(usable), " of ", nrow(md))
if (!is.null(usable$coverage_frac)) {
  partial <- usable$plot_id[usable$coverage_frac < 1]
  if (length(partial)) {
    message("  CAVEAT -- part of `observed` is modelled, not measured, for: ",
            paste(partial, collapse = ", "),
            " (step 2's decay curve fills below the deepest sampled layer)")
  }
}
with_prior <- sum(is.finite(usable$prior))
message("  with a prior value: ", with_prior,
        if (with_prior < nrow(usable)) "  <- limits every tier that uses `prior`" else "")

# --- which tier does this dataset support? ----------------------------------
message("\n=== Tier recommendation ===")
tiers <- tier_recommendation(
  n = with_prior, n_covariates = length(COVARIATES),
  n_locations = nrow(usable)
)
print(tiers)
write.csv(tiers, "outputs/tier_recommendation.csv", row.names = FALSE)

# --- Tier 0: the area-wide estimate -----------------------------------------
# A complete deliverable on its own, not a stepping stone.
message("\n=== Tier 0: Normal-Normal area update ===")
prior_mean <- mean(usable$prior, na.rm = TRUE)
prior_sd   <- mean(usable$prior_sd, na.rm = TRUE)

t0 <- tier0_area_update(usable$observed, prior_mean, prior_sd)
message(sprintf("  prior      %.2f +/- %.2f", t0$prior_mean, t0$prior_sd))
message(sprintf("  evidence   %.2f +/- %.2f  (SE of the mean, n = %d; raw SD %.2f)",
                t0$evidence_mean, t0$evidence_sd, t0$n, t0$evidence_sd_raw))
message(sprintf("  POSTERIOR  %.2f +/- %.2f   CV %.1f%%",
                t0$posterior_mean, t0$posterior_sd, 100 * t0$posterior_cv))
message(sprintf("  weight on the prior: %.1f%%", 100 * t0$prior_weight))

# does the area-wide estimate meet the user's target?
prec <- test_management_precision(t0$posterior_mean, t0$posterior_sd,
                                  margin = TARGET_MARGIN,
                                  confidence = TARGET_CONFIDENCE)
message(sprintf("  target %s: margin of error %.2f (%.1f%% of the mean) -> %s",
                prec$target, prec$margin_of_error, 100 * prec$relative_moe,
                if (isTRUE(prec$passes)) "PASSES" else "does not pass yet"))
if (!isTRUE(prec$passes)) {
  plan <- cores_needed_for_target(t0$posterior_mean, t0$evidence_sd_raw,
                                  prior_sd = t0$prior_sd,
                                  margin = TARGET_MARGIN,
                                  confidence = TARGET_CONFIDENCE)
  message(sprintf("  to hit the target: ~%d cores alone, ~%d with the prior helping",
                  plan$n_frequentist, plan$n_with_prior))
}
saveRDS(t0, "outputs/tier0_area_update.rds")

# --- Tier 1: is the prior biased? -------------------------------------------
message("\n=== Tier 1: calibration against the prior ===")
t1 <- tier1_calibration(usable)
message(sprintf("  observed = %.2f + %.3f x prior   (R2 %.3f, sigma %.2f, n = %d)",
                t1$intercept, t1$slope, t1$r_squared, t1$sigma, t1$n))
if (!is.null(t1$slope_ci)) {
  message(sprintf("  slope 95%% CI %.3f to %.3f -- %s",
                  t1$slope_ci[1], t1$slope_ci[2],
                  if (t1$unbiased) "consistent with slope 1 (no rescaling needed)"
                  else "excludes 1, so the prior needs rescaling, not just an offset"))
}
saveRDS(t1, "outputs/tier1_calibration.rds")

# --- R1: how dependent are prior and evidence? ------------------------------
message("\n=== Prior-evidence dependence (finding R1) ===")
rho <- prior_evidence_correlation(usable)
if (!is.null(rho)) saveRDS(rho, "outputs/prior_evidence_rho.rds")

# --- Tiers 2-4 --------------------------------------------------------------
if (!FIT_BAYES) {
  message("\n=== Tiers 2-4 skipped ===")
  message("  FIT_BAYES is FALSE. Recommended ceiling is ",
          attr(tiers, "ceiling"), ", so fitting them would produce parameters ",
          "the data cannot identify. Set FIT_BAYES <- TRUE to fit anyway ",
          "(useful as a pipeline check, not as a result to report).")
} else {
  message("\n=== Tiers 2-4: candidate model set ===")
  std <- standardize_training(usable, c("prior", COVARIATES, "x", "y"))
  model_data <- std$data
  saveRDS(std$stats, "outputs/std_lookup.rds")   # a grid MUST reuse these

  specs <- tier_model_set(COVARIATES, use_gp = TRUE)
  fits  <- fit_tier_models(specs, model_data)

  message("\n--- sampling diagnostics (the gate) ---")
  diag <- model_diagnostics(fits)
  print(diag)

  message("\n--- LOO / WAIC ---")
  cmp <- compare_tier_models(fits, diag)
  print(cmp$loo)

  message("\n--- GP hyperparameters: informed by data, or by their priors? ---")
  for (nm in names(fits)) {
    g <- gp_prior_check(fits[[nm]])
    if (!is.null(g)) { cat("\n", nm, "\n"); print(g) }
  }

  # PSIS-LOO is unreliable at small n, so refit-per-fold is the real check.
  best <- cmp$loo$model[1]
  message("\n--- manual leave-one-out on '", best, "' + mean-only baseline ---")
  mloo <- manual_loo(specs[[best]], model_data)
  print(mloo[, c("plot_id", "observed", "pred_mean", "model_error",
                 "baseline_error", "within_95")])

  saveRDS(fits, "outputs/tier_fits.rds")
  saveRDS(cmp,  "outputs/tier_comparison.rds")
  saveRDS(mloo, "outputs/tier_manual_loo.rds")
}

message("\nDone. Tier 0 is the reportable result for this dataset.")
