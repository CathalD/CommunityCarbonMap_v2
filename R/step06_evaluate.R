# Step 14 -- diagnostics and model evaluation.
#
# Order matters: sampling diagnostics FIRST, then LOO/WAIC. A model that did
# not sample cleanly cannot be a "winner" whatever its elpd says, so
# model_diagnostics() is the gate and compare_tier_models() reports the gate
# result alongside the ranking rather than after it.
#
# Replaces the old step 8 (compare_prior_vs_model): the "does the model beat
# the prior?" question is now the baseline comparison inside manual_loo().

# --- sampling diagnostics ---------------------------------------------------

model_diagnostics <- function(fits) {
  rows <- lapply(names(fits), function(nm) {
    fit <- fits[[nm]]
    s  <- summary(fit)
    np <- brms::nuts_params(fit)
    div <- sum(np$Value[np$Parameter == "divergent__"], na.rm = TRUE)

    # fixed effects plus spectral/GP hyperparameters, whichever are present
    blocks <- list(s$fixed, s$spec_pars, s$gp)
    blocks <- blocks[!vapply(blocks, is.null, logical(1))]
    all_par <- do.call(rbind, lapply(blocks, function(b) {
      data.frame(Rhat = b[["Rhat"]], Bulk = b[["Bulk_ESS"]], Tail = b[["Tail_ESS"]])
    }))

    data.frame(
      model        = nm,
      n_params     = nrow(all_par),
      max_rhat     = max(all_par$Rhat, na.rm = TRUE),
      min_bulk_ess = min(all_par$Bulk, na.rm = TRUE),
      min_tail_ess = min(all_par$Tail, na.rm = TRUE),
      n_divergent  = div,
      stringsAsFactors = FALSE
    )
  })
  d <- do.call(rbind, rows)
  d$passes <- d$max_rhat <= 1.01 & d$min_bulk_ess >= 400 &
    d$min_tail_ess >= 400 & d$n_divergent == 0
  d
}

#' Is a GP hyperparameter actually informed by the data?
#'
#' If the posterior for sdgp/lscale simply reproduces its prior, the data said
#' nothing about it and the GP's smoothness is an assumption, not a finding.
#' That must be reported, not interpreted.
gp_prior_check <- function(fit) {
  ps <- brms::prior_summary(fit)
  draws <- as.data.frame(fit)
  gp_pars <- grep("^(sdgp|lscale)_", names(draws), value = TRUE)
  if (!length(gp_pars)) return(NULL)

  data.frame(
    parameter    = gp_pars,
    post_mean    = vapply(gp_pars, function(p) mean(draws[[p]]), numeric(1)),
    post_sd      = vapply(gp_pars, function(p) stats::sd(draws[[p]]), numeric(1)),
    prior        = vapply(gp_pars, function(p) {
      cls <- sub("_.*$", "", p)
      hit <- ps$prior[ps$class == cls]
      if (length(hit) && nzchar(hit[1])) hit[1] else "(brms default)"
    }, character(1)),
    row.names = NULL, stringsAsFactors = FALSE
  )
}

# --- LOO / WAIC -------------------------------------------------------------

#' PSIS-LOO and WAIC, with the small-n caveat surfaced rather than suppressed.
compare_tier_models <- function(fits, diagnostics = NULL) {
  loos  <- lapply(fits, function(f) loo::loo(f))
  waics <- lapply(fits, function(f) suppressWarnings(brms::waic(f)))

  bad_k <- vapply(loos, function(l) sum(l$diagnostics$pareto_k > 0.7), numeric(1))
  n_obs <- vapply(loos, function(l) length(l$diagnostics$pareto_k), numeric(1))

  if (any(bad_k > 0)) {
    message("\nPSIS-LOO reliability: ", sum(bad_k), " of ", sum(n_obs),
            " pointwise estimates have Pareto k > 0.7.")
    message("  At small n this is EXPECTED, not a fitting error -- dropping ",
            "one of a handful of points is a large perturbation, so the ",
            "importance-sampling approximation breaks down. Treat the ranking ",
            "below as indicative and rely on manual_loo() instead.")
  }

  out <- as.data.frame(loo::loo_compare(loos))
  out$model <- rownames(out)
  out$bad_pareto_k <- bad_k[out$model]
  out$n_obs <- n_obs[out$model]

  # which downstream path the winner implies -- looked up by name, because
  # subsetting the fit list would drop an attribute
  out$architecture <- unname(model_architecture(out$model))

  if (!is.null(diagnostics)) {
    out$sampling_ok <- diagnostics$passes[match(out$model, diagnostics$model)]
    if (any(!out$sampling_ok, na.rm = TRUE)) {
      message("\nModels failing sampling diagnostics cannot be treated as ",
              "winners regardless of elpd rank: ",
              paste(out$model[!out$sampling_ok], collapse = ", "))
    }
  }

  rownames(out) <- NULL
  list(loo = out,
       waic = as.data.frame(loo::loo_compare(waics)),
       loo_objects = loos)
}

# --- manual LOO + baseline --------------------------------------------------

#' Exact leave-one-out: refit with each observation held out and predict it.
#'
#' Slow (one Stan compile per fold) but trustworthy where PSIS-LOO is not.
#' Also computes the naive baseline -- predicting the training-fold mean.
#' A model that cannot beat that baseline is not earning its complexity, and
#' at small n that is a real outcome rather than a bug.
manual_loo <- function(formula, data, id_col = "plot_id", response = "observed",
                       ...) {
  rows <- lapply(seq_len(nrow(data)), function(i) {
    train <- data[-i, , drop = FALSE]
    test  <- data[i, , drop = FALSE]

    fit <- tryCatch(fit_brms_isolated(formula, train, ...),
                    error = function(e) NULL)
    if (is.null(fit)) return(NULL)

    # Two different questions, two different posteriors:
    #   epred   -- where is the MEAN of the process? (no residual scatter)
    #   predict -- where would a NEW CORE land?      (mean + residual sigma)
    # Coverage is about a held-out core, so the interval has to come from
    # posterior_predict. Scoring it against the epred interval asks whether a
    # single core equals the area average, which it never does -- that reads as
    # a badly miscalibrated model when nothing is wrong.
    epred <- brms::posterior_epred(fit, newdata = test, allow_new_levels = TRUE)
    ppd   <- brms::posterior_predict(fit, newdata = test, allow_new_levels = TRUE)
    obs   <- test[[response]]

    data.frame(
      plot_id      = as.character(test[[id_col]]),
      observed     = obs,
      pred_mean    = mean(epred),
      mean_sd      = stats::sd(epred),                       # uncertainty in the mean
      pred_sd      = stats::sd(ppd),                         # uncertainty in a new core
      lower95      = unname(stats::quantile(ppd, 0.025)),
      upper95      = unname(stats::quantile(ppd, 0.975)),
      model_error  = obs - mean(epred),
      # the trivial competitor: the mean of everything except this point
      baseline_pred  = mean(train[[response]], na.rm = TRUE),
      baseline_error = obs - mean(train[[response]], na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  res <- do.call(rbind, rows[!vapply(rows, is.null, logical(1))])
  res$within_95 <- res$observed >= res$lower95 & res$observed <= res$upper95

  model_mae    <- mean(abs(res$model_error))
  baseline_mae <- mean(abs(res$baseline_error))

  # An intercept-only model IS the mean-only baseline, so a tie there is
  # arithmetic, not a finding. Saying "red flag" about it sends the reader
  # looking for a fault that does not exist.
  rhs <- trimws(deparse(formula[[length(formula)]]))
  intercept_only <- identical(rhs, "1")

  message(sprintf("\nHeld-out MAE  model %.3f  vs  mean-only baseline %.3f",
                  model_mae, baseline_mae))
  if (intercept_only) {
    message("  The winning model is intercept-only, which is the baseline ",
            "written as a Bayesian model -- the two MAEs agreeing is expected. ",
            "The real finding is upstream: no candidate with covariates or ",
            "spatial structure beat it.")
  } else if (model_mae >= baseline_mae) {
    message("  The model does NOT beat predicting the training mean. With ",
            "real covariates and adequate n this is a red flag worth ",
            "investigating, not an expected small-n artefact.")
  }
  message(sprintf("  95%% predictive-interval coverage: %.0f%% (%d of %d)",
                  100 * mean(res$within_95), sum(res$within_95), nrow(res)))
  message("  This is the interval for a NEW CORE, so ~95% is the target. ",
          "Well below that means the model is overconfident; well above ",
          "means it is hedging more than the data require.")

  attr(res, "model_mae") <- model_mae
  attr(res, "baseline_mae") <- baseline_mae
  res
}

# --- prior/evidence dependence ---------------------------------------------

#' How correlated are the prior and the local evidence? (finding R1)
#'
#' The Normal-Normal update assumes they are independent. They are not: both
#' describe the same landscape. This estimates the correlation so the R1
#' sensitivity analysis uses a measured starting point instead of an assumed
#' zero. At small n it is noisy -- report the CI, not the point estimate.
prior_evidence_correlation <- function(data, response = "observed",
                                       prior = "prior") {
  d <- data[is.finite(data[[response]]) & is.finite(data[[prior]]), , drop = FALSE]
  if (nrow(d) < 4) {
    message("n = ", nrow(d), ": too few paired values to estimate rho.")
    return(NULL)
  }
  ct <- stats::cor.test(d[[response]], d[[prior]])
  message(sprintf("Prior-evidence correlation rho = %.3f (95%% CI %.3f to %.3f, n = %d)",
                  ct$estimate, ct$conf.int[1], ct$conf.int[2], nrow(d)))
  message("  Feed this into the R1 sensitivity analysis. rho = 0 is the ",
          "assumption the standard update makes; if the CI excludes 0 that ",
          "assumption is measurably wrong.")
  list(rho = unname(ct$estimate), ci = ct$conf.int, n = nrow(d), test = ct)
}
