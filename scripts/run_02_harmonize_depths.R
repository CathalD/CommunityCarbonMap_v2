source("R/step02_harmonize_depths.R")

soil_data  <- read.csv("data/soil_cores_raw.csv")
harmonized <- harmonize_core_depths(soil_data)

dir.create("outputs", showWarnings = FALSE)
write.csv(harmonized, "outputs/soil_cores_harmonized.csv", row.names = FALSE)
print(harmonized)

# Check against the spreadsheet: summing the 0-15 and 15-30 stocks for a core
# must reproduce its 0-30 cm value on sheet 4 of
# data/soil_carbon_calculation.xlsx. If they disagree, the spreadsheet is right.
shallow <- harmonized[harmonized$bottom <= 30, ]
totals <- tapply(shallow$stock_kg_m2, shallow$plot_id, sum, na.rm = TRUE)
cat("\n0-30 cm stock by core (kg C/m2), MEASURED only -- compare to sheet 4:\n")
print(round(totals, 3))

# With the exponential tail filled in, so the cores can be compared against
# 0-30 cm and 0-1 m map products on the same depth basis.
to30  <- harmonized[harmonized$bottom <= 30, ]
to100 <- harmonized[harmonized$bottom <= 100, ]
cat("\n0-30 cm and 0-100 cm stock by core (kg C/m2), measured + extrapolated:\n")
print(round(data.frame(
  d0_30  = tapply(to30$stock_total_kg_m2,  to30$plot_id,  sum, na.rm = TRUE),
  d0_100 = tapply(to100$stock_total_kg_m2, to100$plot_id, sum, na.rm = TRUE),
  decay_k = tapply(harmonized$decay_k, harmonized$plot_id, function(x) x[1])
), 3))
