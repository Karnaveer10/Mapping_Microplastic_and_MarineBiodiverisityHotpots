# ============================================================
# STEP 8 - BUILD THE HOTSPOT TABLE  (the main result)
# ============================================================
# WHAT THIS STEP DOES
#   This is the core step. It combines everything so far into one
#   analysis-ready table where every row is a grid cell and every column
#   is a measure or a label.
#
#   The pipeline used here is the pipe operator |> :
#     readRDS(...) |> assign_cells() |> summarise()
#   It means "take this object and pass it as the FIRST argument to the
#   next function". It lets us write the steps in the order they happen,
#   instead of nesting brackets.
#
#   The chain is:
#     1. aggregate_grid()  - summarise all points per cell (step 8, part 1)
#     2. score_hotspots()  - turn those numbers into hotspot labels
#
# OUTPUTS
#   data/processed/grid_analysis.rds    - full object including map shapes
#   data/processed/grid_analysis.gpkg   - openable in QGIS / ArcGIS
#   data/processed/grid_analysis.csv    - plain table, easy to inspect
#   outputs/tables/grid_summary.csv     - every cell that has a score
#   outputs/tables/top_10_hotspots.csv  - the ten best cells
#   outputs/tables/top_20_hotspots.csv  - the twenty best cells
#
# WHY WRITE THE DATA THREE TIMES?
#   .rds  - fastest for R (keeps geometry)
#   .gpkg - the standard format for GIS software
#   .csv  - human readable, easy to paste into a report
#
# IMPORTANT INTERPRETATION NOTE
#   "Effective hotspot" means high pollution AND high recorded richness in
#   the same cell. It is an OBSERVED CO-OCCURRENCE, not proof that
#   microplastics caused the biodiversity pattern.
# ============================================================


# ---- Set-up -----------------------------------------------------------------
source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()


# ---- Load the pieces produced by earlier steps ------------------------------
grid       <- readRDS("data/interim/grid_0.5deg.rds")
mp_points  <- readRDS("data/interim/microplastics_joined.rds")
bio_points <- readRDS("data/interim/biodiversity_joined.rds")


# ---- 1. Summarise every cell, then score it ---------------------------------
# aggregate_grid() does the group_by() + summarise() for both datasets
# and attaches the results to the grid.
#
# score_hotspots() then adds: P, B, hotspot_score, pollution_hotspot,
# biodiversity_hotspot, effective_hotspot and rank.
# We pass cfg$hotspot_domain so the threshold domain is configurable
# ("all_observed" vs "co_sampled").
analysis <- aggregate_grid(mp_points, bio_points, grid) |>
  score_hotspots(cfg$hotspot_percentile, domain = cfg$hotspot_domain)


# ---- 2. Save the full analysis object ---------------------------------------
# The .rds keeps the geometry, so the map-making step can draw it directly.
saveRDS(analysis, "data/processed/grid_analysis.rds")

# The .gpkg (GeoPackage) is the standard interchange format for GIS.
# delete_dsn = TRUE overwrites a previous file instead of appending a layer.
# quiet = TRUE suppresses the message sf prints on every write.
sf::st_write(analysis, "data/processed/grid_analysis.gpkg",
             delete_dsn = TRUE, quiet = TRUE)

# The plain CSV has the geometry removed, since a CSV cannot store shapes.
readr::write_csv(sf::st_drop_geometry(analysis),
                 "data/processed/grid_analysis.csv")


# ---- 3. Save the ranked tables ----------------------------------------------
# Step A: keep only the cells that actually have a score.
#   Cells with no data on either side have hotspot_score = NA and cannot
#   be ranked, so they are excluded here (they still appear on the maps).
ranked <- analysis |>
  sf::st_drop_geometry() |>
  dplyr::filter(!is.na(hotspot_score)) |>
  dplyr::arrange(rank)          # rank 1 (best) first

# Step B: save every ranked cell.
readr::write_csv(ranked, "outputs/tables/grid_summary.csv")

# Step C: save just the top ten.
readr::write_csv(head(ranked, 10), "outputs/tables/top_10_hotspots.csv")

# Step D: save the top twenty (cfg$top_n).
readr::write_csv(head(ranked, cfg$top_n),
                 "outputs/tables/top_20_hotspots.csv")