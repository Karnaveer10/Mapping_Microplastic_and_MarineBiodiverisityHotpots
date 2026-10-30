# ============================================================
# STEP 5 - JOIN THE OBSERVATIONS TO THE GRID  (spatial join)
# ============================================================
# WHAT THIS STEP DOES
#   This is the spatial join: it asks, for every observation,
#   "which grid cell do you belong to?"
#
#   After this step each point table carries a new column called cell_id
#   such as "IO_72.5_-18.0". Once the points and the grid share that one
#   common column, we can summarise them with a simple table join.
#
# WHY THIS MATTERS
#   Grouping by cell_id (step 8) is only possible because of this step.
#   It is the point where "raw scattered measurements" becomes
#   "values per location".
#
# OUTPUTS
#   data/interim/microplastics_joined.rds
#   data/interim/biodiversity_joined.rds
#   outputs/tables/spatial_join_summary.csv  - how many points matched
#
# NOTE ON MISSING
#   A point that falls in no cell keeps cell_id = NA. We never delete it
#   and never treat it as zero - it simply stays outside the analysis and
#   is counted in the summary file so the reader can check nothing was lost.
# ============================================================


# ---- Set-up -----------------------------------------------------------------
source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()


# ---- Load the three pieces we need ------------------------------------------
grid <- readRDS("data/interim/grid_0.5deg.rds")                 # from step 4
mp   <- readRDS("data/interim/microplastics_clean.rds")         # from step 2
bio  <- readRDS("data/interim/biodiversity_clean.rds")           # from step 3


# ---- Attach every point to its cell ------------------------------------------
# assign_cells() returns a list, so we take the $data part for each dataset.
mp  <- assign_cells(mp,  grid)
bio <- assign_cells(bio, grid)


# ---- Save the joined points --------------------------------------------------
saveRDS(mp$data,  "data/interim/microplastics_joined.rds")
saveRDS(bio$data, "data/interim/biodiversity_joined.rds")


# ---- Save a small summary table ----------------------------------------------
# bind_rows() stacks the two one-row results into one two-row table,
# so a reader can compare matching success for both datasets at a glance.
readr::write_csv(
  tibble::tibble(
    dataset     = c("microplastics", "biodiversity"),
    assigned    = c(mp$assigned,    bio$assigned),
    unassigned  = c(mp$unassigned,  bio$unassigned)
  ),
  "outputs/tables/spatial_join_summary.csv"
)