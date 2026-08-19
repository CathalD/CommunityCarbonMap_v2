# Generate the workshop EXAMPLE dataset -- fake cores at a fake AOI.
#
# This is teaching data, engineered so every hand calculation in the workshop
# lands on round numbers, and placed in the Hudson Bay Lowlands (just east of
# any real community's area) so the real prior maps and covariates in the
# registries genuinely cover it -- the example can run through the entire
# pipeline, Earth Engine included.
#
# The story the numbers tell:
#   Year 2023 -- a first season of 3 cores  (EX-01, EX-02, EX-03)
#                mean 15, SD 9  ->  SE 5.2 kg C/m2: too uncertain to act on
#   Year 2024 -- 13 more cores, placed where the uncertainty was worst
#                all 16 together: mean 17, SD 8 (exactly) -> SE 2
#   The Bayesian update with the prior map (15 +/- 3) then gives 16.4 +/- 1.7.
#
# Every core has three layers (0-10, 10-25, 25-40 cm), and layer stocks are
# multiples of 0.3 kg C/m2 chosen so that bulk density and %C are exact
# two-decimal numbers that reproduce the stocks EXACTLY -- the workbook, the
# hand calculations, and R all agree to the last digit. EX-01 is the core used
# for the by-hand example (layers 2.4 / 3.0 / 1.8 kg C/m2).
#
# Everything below is base R. Run once; both outputs are small and tracked:
#   data/example_soil_cores.csv
#   data/example_aoi.geojson

# --- the 16 target 0-30 cm stocks (kg C/m2) ---------------------------------
# Chosen as symmetric pairs around 17 so that mean = 17 and sample SD = 8
# EXACTLY (squared deviations sum to 960 = 15 x 64). Year 1 = {6, 15, 24}:
# mean 15, sample SD 9 exactly.
targets <- data.frame(
  core = sprintf("EX-%02d", 1:16),
  year = c(2023, 2023, 2023, rep(2024, 13)),
  T    = c(6, 15, 24,  7, 28, 10, 23, 8, 26, 12, 19, 9, 27, 11, 25, 22),
  stringsAsFactors = FALSE
)
stopifnot(mean(targets$T) == 17, sd(targets$T) == 8)
stopifnot(mean(targets$T[1:3]) == 15, sd(targets$T[1:3]) == 9)

# --- layer design -----------------------------------------------------------
# Layers 0-10, 10-25, 25-40. The 0-30 cm window takes all of layers 1-2 and
# 5/15 = 1/3 of layer 3, so  T = L1 + L2 + L3/3.  L3 is picked so that
# L1 + L2 is a multiple of 0.3, then L1 is ~40% of it (rounded to 0.3).
layer_stocks <- function(T) {
  if (T == 6) return(c(2.4, 3.0, 1.8))          # EX-01, the hand-calc core
  L3 <- c("0" = 1.8, "1" = 1.2, "2" = 0.6)[[as.character(T %% 3)]]
  rest <- T - L3 / 3
  L1 <- round(0.4 * rest / 0.3) * 0.3
  c(L1, rest - L1, L3)
}

# --- bulk density / %C that reproduce each stock exactly --------------------
# stock (kg C/m2) = BD (g/cm3) x %C/100 x thickness (cm) x 10
#   layer 1 (10 cm):  stock = BD x %C        -> %C = L1 / BD
#   layers 2-3 (15):  stock = 1.5 x BD x %C  -> %C = L / (1.5 BD)
# BD candidates are divisors that leave %C exact at 2 decimals.
pick_bd <- function(stock, thickness, prefer) {
  for (bd in prefer) {
    C <- stock / (bd * thickness / 10)
    if (abs(round(C, 2) - C) < 1e-9) return(c(bd = bd, C = round(C, 2)))
  }
  stop("no exact BD/%C for stock ", stock)
}

bd1 <- c(0.8, 0.6, 0.75, 1.2, 1.5)     # EX-01 gets 0.8 -> %C = 3.00
bd2 <- c(1.0, 0.8, 1.25)               # EX-01 gets 1.0 -> %C = 2.00
bd3 <- c(1.2, 1.0, 0.8, 1.25)          # EX-01 gets 1.2 -> %C = 1.00

# --- core locations ---------------------------------------------------------
# Inside the example AOI (Hudson Bay Lowlands, east of any real community's
# area). Year-1 cores spread wide; year-2 cores fill the gaps.
coords <- matrix(c(
  -86.58, 55.30,  -86.46, 55.40,  -86.34, 55.28,           # 2023
  -86.59, 55.42,  -86.53, 55.36,  -86.55, 55.26,  -86.49, 55.31,
  -86.44, 55.25,  -86.47, 55.44,  -86.41, 55.34,  -86.39, 55.43,
  -86.36, 55.38,  -86.33, 55.33,  -86.37, 55.26,  -86.32, 55.42,
  -86.51, 55.45
), ncol = 2, byrow = TRUE)

# --- assemble the raw table (one row per SLICE, same shape as a field csv) --
rows <- list()
for (i in seq_len(nrow(targets))) {
  L <- layer_stocks(targets$T[i])
  stopifnot(abs(L[1] + L[2] + L[3] / 3 - targets$T[i]) < 1e-9)
  lay <- rbind(
    c(pick_bd(L[1], 10, c(bd1[(i - 1) %% length(bd1) + 1], bd1)), t = 10),
    c(pick_bd(L[2], 15, c(bd2[(i - 1) %% length(bd2) + 1], bd2)), t = 15),
    c(pick_bd(L[3], 15, c(bd3[(i - 1) %% length(bd3) + 1], bd3)), t = 15)
  )
  for (j in 1:3) {
    rows[[length(rows) + 1]] <- data.frame(
      year = targets$year[i],
      `Core Id`   = targets$core[i],
      `Sample Id` = sprintf("%s-%d", targets$core[i], j),
      Latitude    = coords[i, 2],
      Longitude   = coords[i, 1],
      Depth       = lay[j, "t"],                       # slice THICKNESS, cm
      `Bulk Density` = lay[j, "bd"],
      OM  = round(lay[j, "C"] * 1.724, 2),             # conventional C->OM
      SOC = lay[j, "C"],                               # percent
      `Organic Carbon Density (g/cm^3)` = lay[j, "bd"] * lay[j, "C"] / 100,
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
}
d <- do.call(rbind, rows)

# --- verify: the raw values reproduce every target stock exactly ------------
q <- d$`Bulk Density` * d$SOC / 100                    # g C / cm3
top <- ave(d$Depth, d$`Core Id`, FUN = function(x) cumsum(x) - x)
bot <- top + d$Depth
ov030 <- pmax(0, pmin(bot, 30) - pmax(top, 0))
s030 <- tapply(q * ov030 * 10, d$`Core Id`, sum)[targets$core]
stopifnot(max(abs(s030 - targets$T)) < 1e-9)
stopifnot(abs(mean(s030) - 17) < 1e-9, abs(sd(s030) - 8) < 1e-9)

write.csv(d, "data/example_soil_cores.csv", row.names = FALSE, quote = FALSE)

# --- the example AOI --------------------------------------------------------
aoi <- '{
  "type": "FeatureCollection",
  "name": "example_aoi",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [{
    "type": "Feature",
    "properties": { "name": "Workshop example area",
                    "note": "fictional AOI in the Hudson Bay Lowlands; all cores in example_soil_cores.csv are fictional" },
    "geometry": { "type": "Polygon", "coordinates": [[
      [-86.62, 55.26], [-86.45, 55.24], [-86.30, 55.27],
      [-86.30, 55.44], [-86.50, 55.46], [-86.62, 55.42],
      [-86.62, 55.26]
    ]] }
  }]
}'
writeLines(aoi, "data/example_aoi.geojson")

# every core must fall inside the AOI
if (requireNamespace("sf", quietly = TRUE)) {
  a <- sf::st_read("data/example_aoi.geojson", quiet = TRUE)
  p <- sf::st_as_sf(data.frame(coords), coords = c("X1", "X2"), crs = 4326)
  inside <- sf::st_within(p, sf::st_union(a), sparse = FALSE)[, 1]
  stopifnot(all(inside))
}

cat("wrote data/example_soil_cores.csv:", nrow(d), "slices,",
    nrow(targets), "cores\n")
cat("0-30 cm stocks:", paste(s030, collapse = " "), "\n")
cat("all 16: mean", mean(s030), "sd", sd(s030),
    "| year 2023: mean", mean(s030[targets$year == 2023]),
    "sd", sd(s030[targets$year == 2023]), "\n")
