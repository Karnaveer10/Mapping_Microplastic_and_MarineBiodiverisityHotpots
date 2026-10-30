# ============================================================
# CORE TESTS
# ============================================================
# WHAT IS THIS FOR?
#   These tests prove our helper functions still behave correctly.
#   They are small, fast, and use no real data, so we can run them after
#   ANY change to utils.R and immediately know whether we broke something.
#
# HOW TO RUN
#       Rscript tests/test_core.R
#
# WHAT IS stopifnot()?
#   It is R's built-in "assert this is TRUE, otherwise stop".
#   Every line below says what the function SHOULD return.
#   If all of them pass, the script prints "Core tests passed".
# ============================================================


# ---- Load the code we are testing --------------------------------------------
source("config.R")
source("R/utils.R")


# ---- TEST 1: coordinate validation --------------------------------------------
# Input: three points - (0,0) valid, (181,0) impossible longitude, (NA,0) missing.
# Expected: TRUE, FALSE, FALSE.
stopifnot(identical(valid_coordinates(c(0, 181, NA), c(0, 0, 0)),
                    c(TRUE, FALSE, FALSE)))


# ---- TEST 2: rank normalisation ------------------------------------------------
# percent_rank() of 1, 2, 3 must be 0, 0.5, 1 - smallest to largest.
stopifnot(identical(normalise_rank(c(1, 2, 3)), c(0, .5, 1)))

# Missing values must stay missing. They must never become 0.
stopifnot(all(is.na(normalise_rank(c(NA_real_, NA_real_)))))


# ---- TEST 3: grid creation ------------------------------------------------------
# The 1 degree grid over our bounding box must give exactly 127 x 90 = 11,430 cells
#   (147 - 20 + 1 = 128 longitude steps -> 127 columns after alignment,
#    30 - (-60) + 1 = 91 latitude steps -> 90 rows)
# and every cell_id must be unique.
grid <- make_grid(cfg, 1.0)
stopifnot(inherits(grid, "sf"),
          nrow(grid) == 127 * 90,
          !anyDuplicated(grid$cell_id))


# ---- TEST 4: spatial join ---------------------------------------------------------
# Two points, one near the south-west corner and one near the north-east corner.
# Both must be matched to a cell, giving assigned = 2.
points <- sf::st_as_sf(data.frame(id   = 1:2,
                                  lon  = c(20.25, 146.75),
                                  lat  = c(-59.75, 29.75)),
                       coords = c("lon", "lat"),
                       crs    = 4326)

assigned <- assign_cells(points, grid)

stopifnot(assigned$assigned == 2L,
          all(!is.na(assigned$data$cell_id)))


# ---- TEST 5: hotspot scoring ------------------------------------------------------
# A tiny three-cell example we can work out by hand:
#
#   cell | mean_microplastic | species_richness
#   -----+-------------------+------------------
#    a   |         1         |        1
#    b   |         2         |        3
#    c   |         3         |        2
#
# At threshold 0.5:
#   pollution   cutoff = 2  -> only cell c is above it
#   biodiversity cutoff = 2  -> only cell b is above it
#   so NO cell is hot on both (effective_hotspot should be FALSE for all three)
#
# hotspot_score must always equal P x B exactly.
toy <- sf::st_as_sf(data.frame(cell_id             = c("a", "b", "c"),
                               mean_microplastic   = c(1, 2, 3),
                               species_richness    = c(1, 3, 2),
                               geometry            = "POINT EMPTY"),
                    wkt = "geometry",
                    crs = 4326)

scored <- score_hotspots(toy, .5)

stopifnot(isTRUE(all.equal(scored$hotspot_score, scored$P * scored$B,
                           check.attributes = FALSE)))

stopifnot(identical(scored$pollution_hotspot,    c(FALSE, FALSE, TRUE)))
stopifnot(identical(scored$biodiversity_hotspot, c(FALSE, TRUE,  FALSE)))


message("Core tests passed")