# ============================================================
# STEP 4 - BUILD THE SPATIAL GRID
# ============================================================
# WHAT THIS STEP DOES
#   Covers the study area with a checkerboard of identical square cells.
#   At 0.5 degrees the study area becomes 11,430 cells.
#
# WHY USE A GRID AT ALL?
#   Microplastic samples and species sightings are scattered points with
#   no common structure. To compare them we need a shared set of "boxes".
#   A grid gives us that common basis, and it is the standard approach in
#   spatial analysis because:
#     - it is simple to explain,
#     - it is easy to check by hand,
#     - it can be exported and used by other tools.
#
# WHY 0.5 DEGREES?
#   Roughly 55 km x 55 km at the equator. Small enough to separate a
#   coastal hotspot from an offshore one, large enough that most coastal
#   cells receive at least one sample. The 1.0 degree version is tested
#   later in the sensitivity analysis (step 10) to prove the answer does
#   not depend on this choice.
#
# WHY IS THERE ONLY ONE LINE OF CODE?
#   Because the real work is done by make_grid() in R/utils.R. This file
#   only has to call it and save the result - that separation is what keeps
#   the code testable.
# ============================================================


# ---- Set-up -----------------------------------------------------------------
source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()


# ---- Create the grid and save it --------------------------------------------
# make_grid() uses cfg$grid_degrees by default (0.5).
# saveRDS() writes the result so steps 5, 8, 9 and 11 can reuse the exact
# same grid instead of rebuilding it.
saveRDS(make_grid(cfg), "data/interim/grid_0.5deg.rds")