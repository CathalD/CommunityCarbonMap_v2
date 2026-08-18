# Run once per machine. Installs everything the workshop scripts touch.

pkgs <- c(
  "terra", "sf",
  "soilassessment", "aqp",
  "tidymodels", "ranger",
  "spdep", "gstat",
  "targets", "tarchetypes",
  "ggplot2",
  # step 14 -- the model tier ladder. brms compiles Stan models, so the first
  # fit takes a minute or two; callr runs each fit in a clean child process.
  "brms", "callr", "loo"
)

missing <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(missing)) install.packages(missing)

# Optional / later -- see the workshop's "Core packages" section:
# install.packages("rgee")                    # Earth Engine bridge
# install.packages("inlabru")                  # advanced Bayesian, Version 2
# INLA installs from its own repo, not CRAN:
# install.packages("INLA", repos = c(getOption("repos"), INLA = "https://inla.r-inla-download.org/R/stable"))
