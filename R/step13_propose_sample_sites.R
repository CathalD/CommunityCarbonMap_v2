# Step 16 -- Iterative sampling
#
# Question: where should the next field visit go?
#
# Start simple: rank candidate cells by posterior SD (+ optional
# |z-residual|), return the coordinates of the top n. This is the seed for a
# proper space-filling / value-of-information design later -- preferring
# high posterior uncertainty, high standardized residuals, poor model
# performance, unexplained spatial structure, and management importance.

propose_next_sample_sites <- function(posterior_sd, z_residual = NULL, n = 10) {
  library(terra)

  score <- posterior_sd
  if (!is.null(z_residual)) {
    score <- score + abs(resample(z_residual, posterior_sd))
  }

  top_cells <- which(rank(-values(score), na.last = "keep") <= n)
  xyFromCell(score, top_cells)
}
