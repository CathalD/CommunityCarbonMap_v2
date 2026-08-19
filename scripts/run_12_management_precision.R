# Step 12 -- test the posterior map against the USER'S precision target.
#
# Set the two numbers below to your management requirement. The map passes at
# a pixel when z x SD <= margin x mean, i.e. the margin of error at your
# chosen confidence is inside your chosen tolerance.

source("R/step12_management_precision.R")
library(terra)

TARGET_MARGIN     <- 0.20   # +/- 20% of the estimate
TARGET_CONFIDENCE <- 0.80   # at 80% confidence  (z = 1.28; 0.95 -> z = 1.96)

posterior_mean <- rast("outputs/posterior/posterior_mean_10m.tif")
posterior_sd   <- rast("outputs/posterior/posterior_sd_10m.tif")

result <- test_management_precision(posterior_mean, posterior_sd,
                                    margin = TARGET_MARGIN,
                                    confidence = TARGET_CONFIDENCE)

dir.create("outputs", showWarnings = FALSE)
writeRaster(result$relative_moe, "outputs/posterior_relative_moe.tif", overwrite = TRUE)
writeRaster(result$passes,       "outputs/posterior_meets_target.tif", overwrite = TRUE)

frac <- as.numeric(global(result$passes, "mean", na.rm = TRUE))
message(sprintf("Target %s: %.0f%% of pixels pass (z = %.2f)",
                result$target, 100 * frac, result$z))
