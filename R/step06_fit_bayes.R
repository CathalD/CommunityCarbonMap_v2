# Step 14 -- Bayesian fitting for Tiers 2-4, and the candidate model set.
#
# TWO ARCHITECTURES, COMPARED RATHER THAN ASSUMED
#
# The prior can enter in one of two mutually exclusive ways:
#
#   prior-as-covariate   observed ~ prior + ...     the model estimates how
#                        much to trust it; the fitted surface IS the posterior
#                        and steps 9-10 must NOT be run afterwards
#
#   prior-as-prior       observed ~ ... (no prior)  the fit is INDEPENDENT
#                        evidence, which step 9/10 then fuses with the prior
#
# Running both in sequence uses the prior twice -- finding A1. The candidate
# set below contains models of each kind so the comparison decides which
# architecture to use, but the choice is exclusive: pick one, then run the
# matching downstream path.
#
# What model comparison can and cannot settle: LOO/WAIC score prediction of
# held-out cores. Both architectures can fit the same cores equally well; where
# they differ is the posterior UNCERTAINTY, which LOO does not penalise for a
# double-counted prior. So the comparison ranks predictive skill -- it is not
# evidence that a prior-as-covariate model may also be fed to step 9.

# --- isolated fitting -------------------------------------------------------

# brms is fitted in a clean child process. The main session has tidymodels,
# terra, sf and tidyverse attached, which collectively mask names brms needs
# (gp, ar, discard, fixed, extract, buffer, ...). Isolating the fit is far less
# fragile than maintaining a conflicts_prefer() list.
#
# targets already runs each target in its own process, so calling this from a
# tar_target() nests two processes. That is mildly wasteful and deliberately
# accepted: one fitting path used everywhere beats two that can drift.
fit_brms_isolated <- function(formula, data, chains = 4, iter = 4000,
                              cores = 4, seed = 123, quiet = TRUE, ...) {
  callr::r(
    func = function(formula, data, chains, iter, cores, seed, dots) {
      library(brms)
      do.call(brms::brm, c(list(
        formula = formula,
        data    = data,
        family  = gaussian(),
        chains  = chains,
        iter    = iter,
        cores   = cores,
        seed    = seed,
        # held constant across every brm()-fitted tier so divergences stay a
        # comparable diagnostic signal rather than a per-tier tuning artefact
        control = list(adapt_delta = 0.99, max_treedepth = 15)
      ), dots))
    },
    args = list(formula = formula, data = data, chains = chains,
                iter = iter, cores = cores, seed = seed, dots = list(...)),
    show = !quiet
  )
}

# --- standardization --------------------------------------------------------

#' Standardize predictors and KEEP the training statistics.
#'
#' The saved mean/sd are not a convenience -- a prediction grid standardized
#' with its own mean/sd is a different transformation from the one the model
#' was fitted under, and produces wrong predictions with no error raised.
standardize_training <- function(data, vars) {
  # Silently skipping an absent variable is what made a missing x/y look like a
  # brms bug ("variable x_std not found") three steps downstream, so say it here.
  gone <- base::setdiff(vars, names(data))
  if (length(gone)) {
    warning("no column named ", paste(gone, collapse = ", "),
            " -- any model formula using ", paste0(gone[1], "_std"),
            " will fail.", if ("x" %in% gone || "y" %in% gone)
              " (Coordinates? read the table with add_projected_coords().)",
            call. = FALSE)
  }
  # base:: is spelled out because sessions with the `conflicted` package (or
  # lubridate/terra attached) turn a bare intersect() into a hard error
  vars <- base::intersect(vars, names(data))
  stats_tbl <- data.frame(
    variable = vars,
    mean = vapply(vars, function(v) mean(data[[v]], na.rm = TRUE), numeric(1)),
    sd   = vapply(vars, function(v) stats::sd(data[[v]], na.rm = TRUE), numeric(1)),
    row.names = NULL, stringsAsFactors = FALSE
  )
  # a constant predictor has sd 0 and would divide to Inf
  flat <- stats_tbl$sd == 0 | !is.finite(stats_tbl$sd)
  if (any(flat)) {
    warning("zero variance, left unstandardized: ",
            paste(stats_tbl$variable[flat], collapse = ", "), call. = FALSE)
    stats_tbl$sd[flat] <- 1
  }
  list(data = standardize_with(data, stats_tbl), stats = stats_tbl)
}

#' Apply saved training statistics to new data (e.g. a prediction grid).
standardize_with <- function(data, stats_tbl) {
  for (i in seq_len(nrow(stats_tbl))) {
    v <- stats_tbl$variable[i]
    if (!is.null(data[[v]])) {
      data[[paste0(v, "_std")]] <- (data[[v]] - stats_tbl$mean[i]) / stats_tbl$sd[i]
    }
  }
  data
}

# --- projected coordinates for the spatial tiers ----------------------------

#' Add x / y columns in metres, for gp(x_std, y_std).
#'
#' A GP measures distance between points, so the coordinates must be in a CRS
#' where distance means metres. Longitude/latitude degrees are not (a degree of
#' longitude shrinks toward the poles), and Web Mercator metres are stretched
#' by ~1/cos(latitude) -- at 55 N that is a 1.7x distortion, which would corrupt
#' any fitted length scale. So this projects to the local UTM zone, chosen from
#' the data's own centre.
add_projected_coords <- function(x) {
  library(sf)
  pts <- if (inherits(x, "SpatVector")) sf::st_as_sf(x) else sf::st_as_sf(x)
  ll  <- sf::st_transform(pts, 4326)
  ctr <- suppressWarnings(sf::st_coordinates(sf::st_centroid(sf::st_union(ll))))

  zone <- floor((ctr[1, 1] + 180) / 6) + 1
  epsg <- if (ctr[1, 2] >= 0) 32600 + zone else 32700 + zone   # WGS84 / UTM

  xy <- sf::st_coordinates(sf::st_transform(pts, epsg))
  out <- sf::st_drop_geometry(pts)
  out$x <- xy[, 1]
  out$y <- xy[, 2]
  attr(out, "crs_epsg") <- epsg
  message("  projected coordinates added (EPSG:", epsg, ", UTM zone ", zone, ")")
  out
}

# --- the candidate set ------------------------------------------------------

#' Build the candidate models for the comparison.
#'
#' @param covariates covariate names (unstandardized); "_std" is appended
#' @param use_gp include the GP models (Tier 3). Costs two hyperparameters and
#'   needs distinct locations, so it is worth switching off at very small n.
tier_model_set <- function(covariates = c("ndvi", "elevation", "slope"),
                           use_gp = TRUE) {
  cov_std <- paste0(covariates, "_std")
  f <- function(rhs) stats::as.formula(paste("observed ~", rhs))

  specs <- list(
    # --- reference: no prior, no covariates ---------------------------------
    t0_intercept      = f("1"),
    # --- prior-as-prior: independent evidence, feeds step 9/10 --------------
    t2_covariates     = f(paste(c("1", cov_std), collapse = " + ")),
    # --- prior-as-covariate: self-contained posterior, skips step 9/10 ------
    t1_prior          = f("1 + prior_std"),
    t2_prior_cov      = f(paste(c("1", "prior_std", cov_std), collapse = " + "))
  )
  if (use_gp) {
    specs$t3_gp_nopriorcov <- f(paste(c("1", cov_std, "gp(x_std, y_std)"),
                                      collapse = " + "))
    specs$t3_gp_priorcov   <- f(paste(c("1", "prior_std", cov_std,
                                        "gp(x_std, y_std)"), collapse = " + "))
  }
  specs
}

#' Which architecture does each model belong to?
#'
#' A lookup rather than an attribute on the list: subsetting a list drops its
#' attributes silently, so `specs[c("a","b")]` or dropping a model that failed
#' to fit would lose the tagging exactly when it is needed.
model_architecture <- function(model_names) {
  lookup <- c(
    t0_intercept     = "reference",          # no prior at all
    t2_covariates    = "prior-as-prior",     # independent evidence -> steps 9-10
    t3_gp_nopriorcov = "prior-as-prior",
    t1_prior         = "prior-as-covariate", # fit IS the posterior -> skip 9-10
    t2_prior_cov     = "prior-as-covariate",
    t3_gp_priorcov   = "prior-as-covariate"
  )
  out <- unname(lookup[model_names])
  out[is.na(out)] <- "unknown"
  stats::setNames(out, model_names)
}

#' Fit every candidate. Failures are captured, not fatal -- one model that will
#' not sample should not lose the rest of the comparison.
fit_tier_models <- function(specs, data, ...) {
  fits <- list()
  for (nm in names(specs)) {
    message("fitting ", nm, ": ", deparse(specs[[nm]]))
    fits[[nm]] <- tryCatch(
      fit_brms_isolated(specs[[nm]], data, ...),
      error = function(e) {
        warning("failed to fit ", nm, ": ", conditionMessage(e), call. = FALSE)
        NULL
      }
    )
  }
  fits[!vapply(fits, is.null, logical(1))]
}
