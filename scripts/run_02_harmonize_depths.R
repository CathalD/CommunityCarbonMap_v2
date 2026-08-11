source("R/step02_harmonize_depths.R")

soil_data <- read.csv("data/soil_cores_raw.csv")

# harmonize_core_depths() promotes soil_data to an aqp::SoilProfileCollection
# before calling depthharm() -- see R/step02_harmonize_depths.R for why.
# Still worth checking the harmonized output against a hand calculation on
# one core before trusting it (the workshop's Step 2 worked example: core 1,
# 0-15 cm target -> 35 Mg C/ha from the raw 0-10 and 10-25 layers).
harmonized <- harmonize_core_depths(soil_data)

dir.create("outputs", showWarnings = FALSE)
write.csv(harmonized, "outputs/soil_cores_harmonized.csv", row.names = FALSE)
head(harmonized)
