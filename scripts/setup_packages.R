# ============================================================
# SIMPLE PACKAGE INSTALLATION SCRIPT
# ============================================================

packages <- c("sf", "dplyr", "readr", "ggplot2", "tidyr", 
              "stringr", "spdep", "dbscan", "scales", "purrr", "tibble")

# Find missing packages correctly
new_packages <- packages[!(packages %in% installed.packages()[,"Package"])]

# Install only what's missing
if(length(new_packages) > 0) {
  install.packages(new_packages, repos = "https://cloud.r-project.org")
}

# Load them all
invisible(lapply(packages, library, character.only = TRUE))

message("All project packages are installed and loaded successfully!")