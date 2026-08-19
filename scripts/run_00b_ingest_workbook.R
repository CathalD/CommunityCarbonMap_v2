# Step 0b -- ingest the field workbook from its exported CSV sheets.
#
# Fill in data/soil_carbon_calculation.xlsx (Excel, or Google Sheets -- free,
# and exports CSV without a licence), then export ONE CSV PER SHEET into
# WORKBOOK_DIR. Both apps name them the same way and this script finds them by
# that convention, so the workbook prefix can be anything:
#
#   soil_carbon_calculation.xlsx - 5. R export (layers).csv
#
# Produces the two files the rest of the workflow reads:
#   data/soil_cores_raw.csv   -> run_02_harmonize_depths.R
#   data/field_plots.gpkg     -> run_03_extract_covariates.R
#
# Run this before run_02. It does not need Earth Engine.

source("R/step00_ingest_workbook.R")

WORKBOOK_DIR <- "data"   # where the exported sheet CSVs live

message("Reading workbook sheets from ", WORKBOOK_DIR, "/")
sheets <- ingest_workbook(WORKBOOK_DIR)

message("\nWriting the analysis inputs")
message("  ", write_soil_cores_raw(sheets, "data/soil_cores_raw.csv"))
message("  ", write_field_plots_from_workbook(sheets, "data/field_plots.gpkg"))

# The workbook is filled in by hand and exported through a spreadsheet app, so
# check it against the raw source before anything downstream trusts it. Which
# raw file? Pick whichever data/*_soil_cores.csv shares the workbook's core
# IDs -- the shipped workbook matches the example csv; a project workbook
# matches its own raw export.
candidates <- Sys.glob("data/*_soil_cores.csv")
wb_ids <- unique(sheets[["6"]]$plot_id)
raw_csv <- NULL
for (cand in candidates) {
  ids <- unique(read.csv(cand, check.names = FALSE)$`Core Id`)
  if (any(wb_ids %in% ids)) { raw_csv <- cand; break }
}
if (is.null(raw_csv)) {
  message("\nNo raw csv matches the workbook's core IDs (",
          paste(head(wb_ids, 3), collapse = ", "),
          " ...) -- skipping the cross-check. That is fine if the raw values ",
          "only exist inside the workbook itself.")
  check <- NULL
} else {
  message("\nValidating against ", raw_csv)
  check <- validate_workbook_ingest(sheets, raw_csv = raw_csv)
}

dir.create("outputs", showWarnings = FALSE)
if (!is.null(check)) {
  write.csv(check, "outputs/workbook_ingest_check.csv", row.names = FALSE)
  print(check)
}
