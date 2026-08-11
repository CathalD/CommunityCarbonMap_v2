source("R/step16_propose_sample_sites.R")
library(terra)

posterior_sd    <- rast("outputs/posterior/posterior_sd_10m.tif")
candidate_sites <- propose_next_sample_sites(posterior_sd, n = 10)

write.csv(candidate_sites, "outputs/proposed_sample_sites.csv", row.names = FALSE)
