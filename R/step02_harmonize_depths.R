# Step 2 -- Process and harmonize the ground data
#
# Question: what did we actually measure in the field, and how do we turn
# it into the variable we want to map?
#
# Chain: field measurements -> carbon calculation -> depth harmonization ->
# final response variable.
#
# NOTE: depthharm() does not accept a plain data.frame -- it reaches into
# soildata@horizons, i.e. it wants an aqp::SoilProfileCollection (that's
# aqp's own S4 class, with a @horizons slot holding exactly this kind of
# flat depth table). Promote the flat table with aqp::depths() first.
#
# Still unverified: whether depthharm() expects the top/bottom columns to
# be literally named "top"/"bottom" once inside the SPC, and whether
# var.name = "soc" must match the column name exactly (it does here) or a
# harmonized-name convention. If this still errors, run
# `print(soilassessment::depthharm)` in the console and send the body back
# -- faster than guessing again.

harmonize_core_depths <- function(soil_data,
                                   target_depths = c(0, 15, 30, 50, 100),
                                   id_col = "plot_id",
                                   top_col = "depth_from",
                                   bottom_col = "depth_to") {
  library(aqp)
  library(soilassessment)

  spc <- soil_data
  aqp::depths(spc) <- stats::as.formula(paste(id_col, "~", top_col, "+", bottom_col))

  depthharm(
    soildata = spc,
    var.name = "soc",
    lam = 0.1,
    d = target_depths
  )
}
