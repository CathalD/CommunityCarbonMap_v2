source("R/step02_harmonize_depths.R")

soil_data <- read.csv("data/soil_cores_raw.csv")

# soilassessment::depthharm()'s expected column names may not exactly match
# soil_cores_raw.csv's (plot_id, depth_from, depth_to, soc, bulk_density,
# coarse_frag) -- check `?soilassessment::depthharm` for the installed
# package version and adjust R/step02_harmonize_depths.R (or this script's
# input columns) before trusting the output. Verify against a hand
# calculation on one core first, per the workshop.
harmonized <- harmonize_core_depths(soil_data)

dir.create("outputs", showWarnings = FALSE)
write.csv(harmonized, "outputs/soil_cores_harmonized.csv", row.names = FALSE)
head(harmonized)
