# Step 2 -- Process and harmonize the ground data
#
# Question: what did we actually measure in the field, and how do we turn
# it into the variable we want to map?
#
# Chain: field measurements -> carbon calculation -> depth harmonization ->
# final response variable.
#
# NOTE: soilassessment::depthharm()'s exact argument names/shape should be
# checked against ?soilassessment::depthharm for the installed package
# version before this is trusted -- verify its output against a hand
# calculation on one core first (see the worked example in the workshop).

harmonize_core_depths <- function(soil_data,
                                   target_depths = c(0, 15, 30, 50, 100)) {
  library(soilassessment)

  depthharm(
    soildata = soil_data,
    var.name = "soc",
    lam = 0.1,
    d = target_depths
  )
}
