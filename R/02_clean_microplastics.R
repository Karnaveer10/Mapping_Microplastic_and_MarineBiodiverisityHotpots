# ============================================================
# STEP 2 - CLEAN THE MICROPLASTIC DATA
# ============================================================
# WHAT THIS STEP DOES
#   1. Loads the helper functions and packages.
#   2. Checks the official NOAA download is present.
#   3. Reads it, removes unusable records, and converts it into
#      map points (longitude / latitude).
#   4. Saves two things:
#        data/interim/microplastics_clean.rds          - the cleaned points
#        outputs/tables/microplastic_cleaning_summary.csv - what was removed
#
# WHY CLEAN AT ALL?
#   Real datasets always contain problems: blank values, text mixed into
#   numbers, coordinates of 0,0 (a classic "unknown" marker), and exact
#   duplicate rows. Left alone, these would distort every average we compute.
#
# WHY SAVE AN .rds FILE?
#   .rds is R's own format. It saves the full data frame INCLUDING the map
#   geometry, so step 5 does not have to redo the cleaning.
#   (.csv would lose the geometry and force us to rebuild it.)
# ============================================================


# ---- Set-up -----------------------------------------------------------------
source("config.R")        # settings
source("R/utils.R")       # helper functions, including read_microplastics()
ensure_dirs()             # create output folders
load_project_packages()   # attach the packages


# ---- Check the input file exists --------------------------------------------
# stopifnot() is a simple assertion: if the condition is FALSE the script
# stops here. Better to fail immediately than to fail confusingly later.
stopifnot(file.exists(cfg$paths$microplastics_raw))


# ---- Read and clean ---------------------------------------------------------
# read_microplastics() is defined in R/utils.R and returns a LIST of two parts:
#   mp$data  -> the cleaned sf points
#   mp$audit -> a one-row table recording exactly what was discarded and why
mp <- read_microplastics(cfg$paths$microplastics_raw, cfg)


# ---- Save the cleaned points for the next step ------------------------------
saveRDS(mp$data, "data/interim/microplastics_clean.rds")


# ---- Save the cleaning audit as a readable CSV ------------------------------
# This is the evidence table for the report:
# "we started with X records and removed Y for these specific reasons."
readr::write_csv(mp$audit,
                 "outputs/tables/microplastic_cleaning_summary.csv")