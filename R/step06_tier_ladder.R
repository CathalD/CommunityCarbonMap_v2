# Step 14 -- the model tier ladder
#
# Replaces the workshop's Step 14 roadmap marker ("don't implement the advanced
# Bayesian model yet") with an actual ladder, ordered by how much data each
# rung needs:
#
#   Tier 0  Normal-Normal update           no spatial structure, no covariates
#   Tier 1  calibration against the prior  observed ~ prior
#   Tier 2  + environmental covariates     observed ~ prior + <covariates>
#   Tier 3  + spatial GP residual          observed ~ ... + gp(x, y)
#   Tier 4  full melding                   prior as a noisy observation of Z(s)
#
# The point of the ladder is NOT to climb it. A community with eight cores and
# the question "is our land a carbon sink, roughly?" is better served by Tier 0
# than by a GP whose hyperparameters only reproduce their priors. Each rung is
# a complete, reportable deliverable on its own.
#
# Tier selection is a human choice. tier_recommendation() below is a decision
# AID -- it reports what the data can carry and stops there.

# --- the decision aid -------------------------------------------------------

#' What tier does this dataset actually support?
#'
#' Counts parameters per tier and compares against n at a rough floor of
#' 10-15 observations per parameter.
#'
#' @param n usable observations AFTER depth harmonization and the covariate
#'   join -- both can drop rows, so pass the count from the modelling table,
#'   not the number of cores collected.
#' @param n_covariates covariates intended for Tier 2+
#' @param n_locations distinct SPATIAL locations. Stacking depth intervals
#'   multiplies rows without adding locations, and a GP learns from locations,
#'   so Tiers 3-4 are judged against this rather than n.
tier_recommendation <- function(n, n_covariates = 3, n_locations = n,
                                floor_per_param = 10) {
  # intercept + sigma are always there; each tier adds its own structure
  params <- c(
    "Tier 0" = 0,                          # conjugate, nothing estimated
    "Tier 1" = 3,                          # intercept + b_prior + sigma
    "Tier 2" = 3 + n_covariates,
    "Tier 3" = 3 + n_covariates + 2,       # + sdgp + lscale
    "Tier 4" = 3 + n_covariates + 2 + 3    # + a, b, delta variance
  )
  # Tiers 3-4 are limited by distinct locations, not by row count
  effective_n <- c(n, n, n, n_locations, n_locations)

  out <- data.frame(
    tier = names(params),
    parameters = as.integer(params),
    n_available = effective_n,
    n_needed = as.integer(params) * floor_per_param,
    stringsAsFactors = FALSE
  )
  out$supported <- out$parameters == 0 | out$n_available >= out$n_needed
  out$obs_per_param <- ifelse(out$parameters == 0, NA_real_,
                              round(out$n_available / out$parameters, 2))

  ceiling_tier <- if (!any(out$supported)) "none" else
    out$tier[max(which(out$supported))]
  attr(out, "ceiling") <- ceiling_tier

  message("Recommended tier ceiling: ", ceiling_tier,
          "  (n = ", n, ", distinct locations = ", n_locations, ")")
  if (ceiling_tier %in% c("Tier 0", "Tier 1")) {
    message("  Higher tiers stay available in the codebase but are not ",
            "supported by this dataset. Borrowing open data raises the ",
            "ceiling faster than adding model structure -- see the ",
            "'Data to borrow' table in docs/code_vs_methods_review.md.")
  }
  out
}

# --- Tier 0 -----------------------------------------------------------------

#' Tier 0 -- Normal-Normal update at the area level.
#'
#' No new maths: this is bayesian_update_normal() from step 9, with the
#' evidence supplied as the sample mean and the STANDARD ERROR of that mean
#' (s/sqrt(m)), which is what makes the posterior tighten as cores are added.
#'
#' Returns a single area-wide estimate. That is the whole deliverable -- not a
#' map, and not a stepping stone to one.
tier0_area_update <- function(observed, prior_mean, prior_sd) {
  stopifnot(length(observed) > 1)
  observed <- observed[is.finite(observed)]
  m <- length(observed)

  evidence_mean <- mean(observed)
  evidence_sd   <- stats::sd(observed) / sqrt(m)   # SE of the mean, not the SD

  post <- bayesian_update_normal(prior_mean, prior_sd, evidence_mean, evidence_sd)

  list(
    tier           = "Tier 0",
    n              = m,
    prior_mean     = prior_mean,
    prior_sd       = prior_sd,
    evidence_mean  = evidence_mean,
    evidence_sd    = evidence_sd,
    evidence_sd_raw = stats::sd(observed),
    posterior_mean = post$posterior_mean,
    posterior_sd   = post$posterior_sd,
    posterior_cv   = post$posterior_sd / post$posterior_mean,
    prior_weight   = (1 / prior_sd^2) /
      (1 / prior_sd^2 + 1 / evidence_sd^2)
  )
}

# --- Tier 1 -----------------------------------------------------------------

#' Tier 1 -- calibrate the prior against the cores.
#'
#' Step 4 already reports the ADDITIVE bias (mean residual). This adds the
#' multiplicative term: if the prior is on a different depth basis, the slope
#' absorbs the scaling and the intercept absorbs the offset, which is the
#' cheapest available answer to finding A6.
#'
#' Plain lm() by default -- three parameters do not need Stan. Set
#' `bayesian = TRUE` for a posterior instead of a point estimate.
tier1_calibration <- function(data, response = "observed", prior = "prior",
                              bayesian = FALSE, ...) {
  f <- stats::as.formula(paste(response, "~", prior))
  d <- data[is.finite(data[[response]]) & is.finite(data[[prior]]), , drop = FALSE]

  if (nrow(d) < 3) {
    stop("Tier 1 needs at least 3 plots with both a value and a prior; have ",
         nrow(d), call. = FALSE)
  }

  if (bayesian) {
    fit <- fit_brms_isolated(f, d, ...)
    return(list(tier = "Tier 1", n = nrow(d), fit = fit, formula = f))
  }

  fit <- stats::lm(f, data = d)
  cf  <- stats::coef(fit)
  ci  <- tryCatch(stats::confint(fit), error = function(e) NULL)

  list(
    tier      = "Tier 1",
    n         = nrow(d),
    fit       = fit,
    formula   = f,
    intercept = unname(cf[1]),
    slope     = unname(cf[2]),
    slope_ci  = if (is.null(ci)) NULL else unname(ci[2, ]),
    r_squared = summary(fit)$r.squared,
    sigma     = summary(fit)$sigma,
    # slope 1 / intercept 0 would mean the prior needs no calibration
    unbiased  = !is.null(ci) && ci[2, 1] <= 1 && ci[2, 2] >= 1
  )
}
