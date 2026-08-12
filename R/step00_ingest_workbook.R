# Step 0 (ingest) -- read the field workbook back in from its CSV sheets.
#
# The workbook is filled in by hand (Excel, or Google Sheets, which is free and
# exports CSV without a licence) and then exported one CSV per sheet. Both apps
# use the same naming convention:
#
#   <workbook name> - <sheet number>. <sheet name>.csv
#   e.g. "soil_carbon_calculation.xlsx - 5. R export (layers).csv"
#
# so the sheets are matched on that suffix and the workbook prefix can be
# anything. Only sheets 5 and 6 feed the analysis -- they were built as clean
# rectangular tables with the exact column names run_02 and run_03 expect.
# Sheets 1-4 are human-facing and carry title/note/band rows above their
# headers, hence the per-sheet `skip`.
#
# Everything read here is checked back against data/community_soil_cores.csv,
# which is the raw source. CSV export writes DISPLAYED values in Excel, so a
# formatted cell can arrive rounded; validate_workbook_ingest() is what catches
# that, along with any hand-edit that broke a formula.

source_once_wb <- function(path) if (!exists("summarize_community_cores")) source(path)
source_once_wb("R/step00_ground_data.R")

WORKBOOK_SHEETS <- data.frame(
  sheet = 1:6,
  name  = c("Instructions", "Core Log", "Sample Data", "Core Summary",
            "R export (layers)", "R export (plots)"),
  skip  = c(0, 3, 4, 3, 0, 0),
  stringsAsFactors = FALSE
)

#' Locate one sheet's CSV inside a directory.
find_sheet_csv <- function(dir, sheet, sheets = WORKBOOK_SHEETS) {
  row <- sheets[sheets$sheet == sheet, ]
  files <- list.files(dir, pattern = "\\.csv$", full.names = TRUE)
  if (!length(files)) return(NA_character_)

  # Exact suffix first -- filenames contain "(", ")" and "." so this avoids
  # having to escape anything for a regex.
  want <- sprintf(" - %d. %s.csv", row$sheet, row$name)
  hit <- files[endsWith(basename(files), want)]
  if (length(hit)) return(hit[1])

  # Fallback: any file whose name carries "<n>. <sheet name>"
  loose <- files[grepl(sprintf("%d. %s", row$sheet, row$name), basename(files), fixed = TRUE)]
  if (length(loose)) return(loose[1])

  NA_character_
}

drop_empty <- function(d) {
  if (!nrow(d)) return(d)
  blank <- function(x) is.na(x) | trimws(as.character(x)) == ""
  keep_rows <- !apply(vapply(d, blank, logical(nrow(d))), 1, all)
  d <- d[keep_rows, , drop = FALSE]
  keep_cols <- !vapply(d, function(x) all(blank(x)), logical(1))
  d <- d[, keep_cols, drop = FALSE]
  # unnamed trailing columns from the export
  d[, !grepl("^(X|V)[0-9]*$", names(d)) | names(d) == "", drop = FALSE]
}

#' Read one sheet. check.names = FALSE because sheets 2-4 carry en-dashes,
#' superscripts and arrows in their headers that R would otherwise mangle.
read_workbook_sheet <- function(dir, sheet, sheets = WORKBOOK_SHEETS) {
  path <- find_sheet_csv(dir, sheet, sheets)
  if (is.na(path)) {
    stop("could not find the CSV for sheet ", sheet, " ('",
         sheets$name[sheets$sheet == sheet], "') in ", dir,
         "\n  expected a file ending: ' - ", sheet, ". ",
         sheets$name[sheets$sheet == sheet], ".csv'",
         "\n  found: ", paste(basename(list.files(dir, pattern = "\\.csv$")),
                              collapse = ", "),
         call. = FALSE)
  }
  d <- utils::read.csv(path, skip = sheets$skip[sheets$sheet == sheet],
                       check.names = FALSE, stringsAsFactors = FALSE,
                       na.strings = c("", "NA", "#N/A"))
  d <- drop_empty(d)          # subsetting drops attributes, so tag it after
  attr(d, "source_file") <- path
  d
}

#' Read every sheet the workbook exported.
ingest_workbook <- function(dir = "data", sheets = WORKBOOK_SHEETS, verbose = TRUE) {
  out <- list()
  for (i in sheets$sheet) {
    nm <- sheets$name[sheets$sheet == i]
    d <- tryCatch(read_workbook_sheet(dir, i, sheets), error = function(e) {
      if (verbose) message("  sheet ", i, " (", nm, "): ", conditionMessage(e))
      NULL
    })
    if (!is.null(d) && verbose) {
      message(sprintf("  sheet %d %-20s %3d rows x %2d cols  <- %s",
                      i, nm, nrow(d), ncol(d), basename(attr(d, "source_file"))))
    }
    out[[as.character(i)]] <- d
  }
  out
}

# --- sheet 5 -> data/soil_cores_raw.csv (step 2's input) --------------------

LAYER_COLS <- c("plot_id", "depth_from", "depth_to", "soc", "bulk_density", "coarse_frag")

write_soil_cores_raw <- function(sheets, dsn = "data/soil_cores_raw.csv") {
  d <- sheets[["5"]]
  if (is.null(d)) stop("sheet 5 (R export (layers)) was not ingested", call. = FALSE)

  missing <- setdiff(LAYER_COLS, names(d))
  if (length(missing)) {
    stop("sheet 5 is missing required column(s): ", paste(missing, collapse = ", "),
         "\n  found: ", paste(names(d), collapse = ", "), call. = FALSE)
  }
  d <- d[, LAYER_COLS, drop = FALSE]
  for (v in setdiff(LAYER_COLS, "plot_id")) d[[v]] <- as.numeric(d[[v]])

  # depthharm() needs intervals sorted with no gaps or overlaps within a core.
  bad <- character(0)
  for (p in unique(d$plot_id)) {
    s <- d[d$plot_id == p, ]
    s <- s[order(s$depth_from), ]
    if (any(s$depth_to <= s$depth_from)) bad <- c(bad, paste0(p, " (non-positive interval)"))
    if (nrow(s) > 1 && any(abs(s$depth_from[-1] - s$depth_to[-nrow(s)]) > 1e-6)) {
      bad <- c(bad, paste0(p, " (gap or overlap between intervals)"))
    }
  }
  if (length(bad)) {
    warning("depth intervals are not contiguous for: ", paste(bad, collapse = "; "),
            "\n  step 2 will fail on these -- fix sheet 3 of the workbook.",
            call. = FALSE)
  }

  utils::write.csv(d, dsn, row.names = FALSE)
  dsn
}

# --- sheet 6 -> data/field_plots.gpkg (step 3's input) ----------------------

PLOT_COLS <- c("plot_id", "longitude", "latitude", "observed")

write_field_plots_from_workbook <- function(sheets, dsn = "data/field_plots.gpkg",
                                            full_coverage_only = TRUE) {
  library(sf)
  d <- sheets[["6"]]
  if (is.null(d)) stop("sheet 6 (R export (plots)) was not ingested", call. = FALSE)

  missing <- setdiff(PLOT_COLS, names(d))
  if (length(missing)) {
    stop("sheet 6 is missing required column(s): ", paste(missing, collapse = ", "),
         "\n  found: ", paste(names(d), collapse = ", "), call. = FALSE)
  }
  for (v in c("longitude", "latitude", "observed")) d[[v]] <- as.numeric(d[[v]])

  if (any(d$longitude > 0, na.rm = TRUE)) {
    warning("sheet 6 has positive longitudes. This AOI is in the western ",
            "hemisphere -- check the sign fix on sheet 2 of the workbook.",
            call. = FALSE)
  }

  # A core that stopped short of the target depth is not an observation of that
  # interval. Sheet 6 flags these; drop them rather than model them.
  if (full_coverage_only && "coverage_flag" %in% names(d)) {
    partial <- grepl("^PARTIAL", d$coverage_flag)
    if (any(partial)) {
      message("  dropping ", sum(partial), " partial-coverage core(s): ",
              paste(d$plot_id[partial], collapse = ", "))
      d <- d[!partial, , drop = FALSE]
    }
  }

  keep <- intersect(c(PLOT_COLS, "units", "depth_basis", "coverage_flag"), names(d))
  pts <- sf::st_as_sf(d[, keep, drop = FALSE],
                      coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
  sf::st_write(pts, dsn, delete_dsn = TRUE, quiet = TRUE)
  dsn
}

# --- validation against the raw source --------------------------------------

#' Check the ingested workbook against data/community_soil_cores.csv.
#'
#' The workbook is the authority for the workshop, but it is filled in by hand
#' and exported through a spreadsheet app, so this recomputes the 0-30 cm stock
#' straight from the raw file and compares. A mismatch means a formula was
#' overtyped, or the CSV export rounded a formatted cell.
validate_workbook_ingest <- function(sheets,
                                     raw_csv = "data/community_soil_cores.csv",
                                     tol = 1e-3) {
  truth <- summarize_community_cores(raw_csv)$per_core
  wb <- sheets[["6"]]
  if (is.null(wb)) {
    warning("sheet 6 not ingested -- cannot validate", call. = FALSE)
    return(invisible(NULL))
  }
  wb$observed <- as.numeric(wb$observed)

  cmp <- merge(
    truth[, c("core_id", "stock_kg_m2", "core_bottom_cm")],
    wb[, c("plot_id", "observed")],
    by.x = "core_id", by.y = "plot_id", all = TRUE
  )
  cmp$difference <- cmp$observed - cmp$stock_kg_m2
  cmp$agrees <- !is.na(cmp$difference) & abs(cmp$difference) <= tol

  n_bad <- sum(!cmp$agrees & !is.na(cmp$observed))
  if (n_bad) {
    warning(n_bad, " core(s) disagree with ", raw_csv,
            " by more than ", tol, " kg C/m2. The raw file wins -- see the ",
            "returned table.", call. = FALSE)
  } else {
    message("  workbook agrees with ", basename(raw_csv), " on all ",
            sum(!is.na(cmp$observed)), " exported core(s) (tol ", tol, ")")
  }
  cmp
}
