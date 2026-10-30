# ============================================================
# STEP 9 - SPATIAL STATISTICS
# ============================================================
# WHAT THIS STEP DOES
#   The maps in step 11 show WHERE the high scores are. This step asks a
#   different, stronger question: are those high values CLUSTERED, or are
#   they just scattered randomly across the map?
#
#   Three tests are run, each answering something different:
#
#   1. MORAN'S I  (moran_i_results.csv)
#      "Is the whole pattern clustered?"
#      One number for the entire map. A positive value near +1 means
#      similar values sit next to each other (clustering). A value near
#      0 means the pattern is random.
#
#   2. GETIS-ORD Gi*  (getis_ord_results.csv)
#      "WHICH specific cells belong to a significant cluster?"
#      This is the test that produces the STATISTICALLY SIGNIFICANT
#      HOTSPOTS mentioned in our deliverables, replacing an arbitrary
#      cut-off with a formal significance test. Each cell gets a z-score
#      and a p-value, and we apply a Benjamini-Hochberg correction because
#      testing thousands of cells at once would otherwise produce many
#      false positives.
#
#   3. DBSCAN  (dbscan_results.csv)
#      "Do the best cells form separate geographical groups?"
#      Unlike the percentile test, DBSCAN does not need a threshold: it
#      finds groups that are naturally dense and leaves isolated cells
#      unclassified. That makes it a good independent check on the
#      hotspot list.
#
# ALL THE LOGIC LIVES IN run_spatial_statistics() IN utils.R
# This file only calls it and saves the three tables it returns.
# ============================================================


# ---- Set-up -----------------------------------------------------------------
source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()


# ---- Load the finished analysis table from step 8 ---------------------------
grid_analysis <- readRDS("data/processed/grid_analysis.rds")


# ---- Run all three tests ----------------------------------------------------
# The returned object is a list with three parts:
#   $moran    - the single Moran's I result
#   $gi       - one row per cell with the Gi* statistics
#   $clusters - one row per high-priority cell with its cluster number
#
# IMPORTANT: if there are too few usable cells the function returns a
# "status" message instead of numbers. We never invent a result.
results <- run_spatial_statistics(grid_analysis, cfg)


# ---- Save the three tables ---------------------------------------------------
readr::write_csv(results$moran,
                 "outputs/tables/moran_i_results.csv")

readr::write_csv(results$gi,
                 "outputs/tables/getis_ord_results.csv")

readr::write_csv(results$clusters,
                 "outputs/tables/dbscan_results.csv")