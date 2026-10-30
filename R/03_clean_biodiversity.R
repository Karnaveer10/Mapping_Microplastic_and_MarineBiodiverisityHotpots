# ============================================================
# STEP 3 - CLEAN THE BIODIVERSITY DATA
# ============================================================
# WHAT THIS STEP DOES
#   Exactly the same job as step 2, but for the OBIS species records.
#
#   1. Checks the official OBIS download is present.
#   2. Reads it, removes unusable records (bad coordinates, outside the
#      study area, or missing a species name).
#   3. Saves:
#        data/interim/biodiversity_clean.rds           - the cleaned points
#        outputs/tables/biodiversity_cleaning_summary.csv - what was removed
#
# A NOTE ON FILE SIZE
#   The OBIS export for the Indian Ocean is over 1 GB. We keep it as an
#   .rds file so later steps load it from disk quickly, and the cleaning
#   function only creates the extra columns we actually need.
#
# WHY REQUIRING A SPECIES NAME MATTERS
#   Species richness is the count of DISTINCT scientific names. A record
#   with a blank species name cannot be counted, so it would silently make
#   a cell look emptier than it really is. Such records are removed.
# ============================================================


# ---- Set-up -----------------------------------------------------------------
source("config.R")        # settings
source("R/utils.R")       # helper functions, including read_biodiversity()
ensure_dirs()             # create output folders
load_project_packages()   # attach the packages


# ---- Check the input file exists --------------------------------------------
stopifnot(file.exists(cfg$paths$biodiversity_raw))


# ---- Read and clean ---------------------------------------------------------
# Returns a list:
#   bio$data  -> cleaned sf points with longitude, latitude,
#                scientific_name and taxonomic_group columns
#   bio$audit -> the one-row table of what was removed
bio <- read_biodiversity(cfg$paths$biodiversity_raw, cfg)


# ---- Save the cleaned points for the next step ------------------------------
saveRDS(bio$data, "data/interim/biodiversity_clean.rds")


# ---- Save the cleaning audit -------------------------------------------------
readr::write_csv(bio$audit,
                 "outputs/tables/biodiversity_cleaning_summary.csv")