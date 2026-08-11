# Creates a tiny synthetic AOI + prior + covariates + field plots under
# data/, so every scripts/run_*.R script can be run immediately, before real
# project data is available. Re-run any time for a fresh toy dataset.
#
# Once real data exists, drop it into data/ under the same filenames and
# skip this script -- nothing downstream changes.

source("R/utils_synthetic_data.R")

generate_synthetic_project(out_dir = "data", seed = 42, n_field = 15, extent_m = 2000)
