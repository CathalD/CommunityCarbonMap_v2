# Collect small, text-only diagnostics into diagnostics/ so they can be pushed
# and read remotely.
#
#   source("scripts/collect_diagnostics.R")
#   system("git add diagnostics && git commit -m 'diagnostics' && git push")
#
# Deliberately NO rasters are copied -- only their metadata and a sampled
# summary, so nothing here is more than a few hundred KB. Raster values are
# never fully loaded, so this is safe to run after an out-of-memory crash.

OUT <- "diagnostics"
dir.create(OUT, showWarnings = FALSE)

MAX_ROWS <- 60      # per table
MAX_CHARS <- 160    # per cell

safe <- function(expr, label = "") {
  tryCatch(expr, error = function(e) paste0("<error", if (nzchar(label)) paste0(" in ", label), ": ",
                                            conditionMessage(e), ">"))
}

# ---- session -------------------------------------------------------------
con <- file(file.path(OUT, "session.txt"), "w")
writeLines(c(
  paste("generated:", Sys.time()),
  paste("R:", R.version.string),
  paste("platform:", R.version$platform),
  "",
  "packages:"
), con)
for (p in c("terra", "sf", "aqp", "tidymodels", "parsnip", "ranger", "rgee",
            "targets", "gstat", "spdep", "ggplot2")) {
  v <- safe(as.character(utils::packageVersion(p)), p)
  writeLines(paste0("  ", p, ": ", v), con)
}
close(con)

# ---- file inventory ------------------------------------------------------
files <- c(list.files("data", full.names = TRUE),
           list.files("outputs", full.names = TRUE, recursive = TRUE))
inv <- data.frame(
  path = files,
  size_mb = round(file.size(files) / 1e6, 3),
  modified = format(file.mtime(files)),
  stringsAsFactors = FALSE
)
write.csv(inv[order(-inv$size_mb), ], file.path(OUT, "files.csv"), row.names = FALSE)

# ---- raster metadata (no values loaded) ----------------------------------
tifs <- list.files("data", pattern = "\\.tif$", full.names = TRUE)
if (length(tifs)) {
  suppressPackageStartupMessages(library(terra))
  rows <- lapply(tifs, function(f) safe({
    r <- rast(f)
    # a regular sample keeps this cheap on a 40M-cell grid
    s <- spatSample(r, size = 5000, method = "regular", na.rm = FALSE)[, 1]
    data.frame(
      file = basename(f), nrow = nrow(r), ncol = ncol(r), nlyr = nlyr(r),
      cells = as.numeric(ncell(r)),
      res_x = res(r)[1], res_y = res(r)[2],
      crs = substr(crs(r, describe = TRUE)$code, 1, 20),
      xmin = ext(r)$xmin, xmax = ext(r)$xmax,
      ymin = ext(r)$ymin, ymax = ext(r)$ymax,
      samp_min = round(min(s, na.rm = TRUE), 4),
      samp_mean = round(mean(s, na.rm = TRUE), 4),
      samp_max = round(max(s, na.rm = TRUE), 4),
      pct_na = round(100 * mean(is.na(s)), 2),
      stringsAsFactors = FALSE
    )
  }, basename(f)))
  rows <- rows[vapply(rows, is.data.frame, logical(1))]
  if (length(rows)) {
    write.csv(do.call(rbind, rows), file.path(OUT, "rasters.csv"), row.names = FALSE)
  }
}

# ---- the small tables, truncated -----------------------------------------
con <- file(file.path(OUT, "tables.txt"), "w")
csvs <- list.files("outputs", pattern = "\\.csv$", full.names = TRUE)
csvs <- csvs[file.size(csvs) < 2e6]
for (f in csvs) {
  writeLines(c(strrep("=", 70), paste("FILE:", f), strrep("=", 70)), con)
  d <- safe(read.csv(f, stringsAsFactors = FALSE, check.names = FALSE), basename(f))
  if (is.data.frame(d)) {
    writeLines(paste0("rows: ", nrow(d), "   cols: ", ncol(d)), con)
    writeLines(paste0("NA per column: ",
                      paste(names(d), colSums(is.na(d)), sep = "=", collapse = ", ")), con)
    d <- head(d, MAX_ROWS)
    d[] <- lapply(d, function(x) substr(as.character(x), 1, MAX_CHARS))
    writeLines(utils::capture.output(print(d, row.names = FALSE)), con)
  } else {
    writeLines(as.character(d), con)
  }
  writeLines("", con)
}
close(con)

# ---- targets state -------------------------------------------------------
con <- file(file.path(OUT, "targets.txt"), "w")
m <- safe({
  suppressPackageStartupMessages(library(targets))
  tar_meta(fields = c("name", "error", "warnings", "seconds", "bytes"))
}, "tar_meta")
if (is.data.frame(m)) {
  bad <- m[!is.na(m$error) | !is.na(m$warnings), , drop = FALSE]
  writeLines("--- targets with errors or warnings ---", con)
  if (nrow(bad)) {
    bad$error <- substr(bad$error, 1, 400)
    bad$warnings <- substr(bad$warnings, 1, 400)
    writeLines(utils::capture.output(print(as.data.frame(bad), row.names = FALSE)), con)
  } else {
    writeLines("(none)", con)
  }
  writeLines(c("", "--- all targets ---"), con)
  writeLines(utils::capture.output(
    print(as.data.frame(m[, c("name", "seconds", "bytes")]), row.names = FALSE)), con)
} else {
  writeLines(as.character(m), con)
}

le <- safe(get(".Last.error", envir = globalenv()), ".Last.error")
writeLines(c("", "--- .Last.error ---",
             substr(paste(utils::capture.output(print(le)), collapse = "\n"), 1, 3000)), con)
close(con)

total <- sum(file.size(list.files(OUT, full.names = TRUE)))
message("wrote ", OUT, "/: ", paste(list.files(OUT), collapse = ", "))
message("total size: ", round(total / 1024, 1), " KB")
message("\nnow run:")
message('  system("git add -A diagnostics && git commit -m diagnostics && git push")')
