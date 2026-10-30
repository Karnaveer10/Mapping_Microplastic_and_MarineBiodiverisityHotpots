# Run with: Rscript tests/test_core.R
source("config.R")
source("R/utils.R")

stopifnot(identical(valid_coordinates(c(0, 181, NA), c(0, 0, 0)), c(TRUE, FALSE, FALSE)))
stopifnot(identical(normalise_rank(c(1, 2, 3)), c(0, .5, 1)))
stopifnot(all(is.na(normalise_rank(c(NA_real_, NA_real_)))))

grid <- make_grid(cfg, 1.0)
stopifnot(inherits(grid, "sf"), nrow(grid) == 127 * 90, !anyDuplicated(grid$cell_id))
points <- sf::st_as_sf(data.frame(id = 1:2, lon = c(20.25, 146.75), lat = c(-59.75, 29.75)), coords = c("lon", "lat"), crs = 4326)
assigned <- assign_cells(points, grid)
stopifnot(assigned$assigned == 2L, all(!is.na(assigned$data$cell_id)))

toy <- sf::st_as_sf(data.frame(cell_id = c("a", "b", "c"), mean_microplastic = c(1, 2, 3), species_richness = c(1, 3, 2), geometry = "POINT EMPTY"), wkt = "geometry", crs = 4326)
scored <- score_hotspots(toy, .5)
stopifnot(isTRUE(all.equal(scored$hotspot_score, scored$P * scored$B, check.attributes = FALSE)))
stopifnot(identical(scored$pollution_hotspot, c(FALSE, FALSE, TRUE)))
stopifnot(identical(scored$biodiversity_hotspot, c(FALSE, TRUE, FALSE)))

message("Core tests passed")
