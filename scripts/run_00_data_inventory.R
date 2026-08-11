# One function, run once, one artifact on disk -- the pattern every
# run_*.R script in this folder follows.

source("R/step00_data_inventory.R")

inventory <- build_data_inventory()

dir.create("outputs", showWarnings = FALSE)
write.csv(inventory, "outputs/data_inventory.csv", row.names = FALSE)
print(inventory)
