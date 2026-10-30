# Shared functions for the Indian Ocean microplastic-biodiversity workflow.
required_packages <- c("sf", "dplyr", "readr", "ggplot2", "tidyr", "stringr", "spdep", "dbscan", "scales", "purrr", "tibble")
project_library <- "renv/library/R-4.6"

configure_project_library <- function() {
  if (dir.exists(project_library)) .libPaths(c(normalizePath(project_library), .libPaths()))
  invisible(.libPaths())
}

configure_project_library()

load_project_packages <- function() {
  configure_project_library()
  missing <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Install required R packages before running: ", paste(missing, collapse = ", "), call. = FALSE)
  invisible(lapply(required_packages, library, character.only = TRUE))
}

ensure_dirs <- function() {
  dirs <- c("data/raw", "data/interim", "data/processed", "outputs/figures", "outputs/maps", "outputs/tables", "outputs/results")
  invisible(lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE))
}

study_area <- function(cfg) sf::st_as_sfc(sf::st_bbox(cfg$study_bbox, crs = sf::st_crs(cfg$crs)))

pick_col <- function(x, choices, required = TRUE) {
  lookup <- setNames(names(x), tolower(names(x)))
  hit <- unname(lookup[tolower(choices)])
  hit <- hit[!is.na(hit)]
  if (!length(hit) && required) stop("Required column absent. Expected one of: ", paste(choices, collapse = ", "), call. = FALSE)
  if (length(hit)) hit[[1]] else NA_character_
}

as_num <- function(x) suppressWarnings(readr::parse_number(as.character(x)))
valid_coordinates <- function(lon, lat) !is.na(lon) & !is.na(lat) & lon >= -180 & lon <= 180 & lat >= -90 & lat <= 90
in_study_area <- function(lon, lat, cfg) lon >= cfg$study_bbox[["xmin"]] & lon <= cfg$study_bbox[["xmax"]] & lat >= cfg$study_bbox[["ymin"]] & lat <= cfg$study_bbox[["ymax"]]

normalise_rank <- function(x) {
  out <- rep(NA_real_, length(x)); ok <- !is.na(x)
  if (sum(ok) == 1L) out[ok] <- 1
  if (sum(ok) > 1L) out[ok] <- dplyr::percent_rank(x[ok])
  out
}

quantile_flag <- function(x, threshold) {
  out <- rep(NA, length(x)); ok <- !is.na(x)
  if (!any(ok)) return(out)
  cutoff <- stats::quantile(x[ok], threshold, names = FALSE, type = 7)
  out[ok] <- x[ok] > cutoff
  out
}

make_grid <- function(cfg, resolution = cfg$grid_degrees) {
  if (!resolution %in% c(0.5, 1.0)) stop("Grid resolution must be 0.5 or 1.0 degrees.", call. = FALSE)
  grid <- sf::st_make_grid(study_area(cfg), cellsize = c(resolution, resolution), square = TRUE, what = "polygons")
  grid <- sf::st_sf(geometry = grid)
  centers <- sf::st_coordinates(sf::st_centroid(grid))
  west <- floor((centers[, 1] - cfg$study_bbox[["xmin"]]) / resolution) * resolution + cfg$study_bbox[["xmin"]]
  south <- floor((centers[, 2] - cfg$study_bbox[["ymin"]]) / resolution) * resolution + cfg$study_bbox[["ymin"]]
  grid$cell_id <- sprintf("IO_%0.1f_%0.1f", west, south)
  dplyr::select(grid, cell_id, geometry)
}

assign_cells <- function(points, grid) {
  idx <- sf::st_intersects(points, grid)
  cell_id <- vapply(idx, function(i) if (length(i)) grid$cell_id[[i[[1]]]] else NA_character_, character(1))
  points$cell_id <- cell_id
  list(data = points, assigned = sum(!is.na(cell_id)), unassigned = sum(is.na(cell_id)))
}

read_microplastics <- function(path, cfg) {
  x <- readr::read_csv(path, show_col_types = FALSE, name_repair = "unique")
  lon_col <- pick_col(x, c("longitude", "lon", "decimalLongitude", "longitude (degree)", "longitude(degree)")); lat_col <- pick_col(x, c("latitude", "lat", "decimalLatitude", "latitude (degree)", "latitude(degree)")); conc_col <- pick_col(x, c("concentration", "microplastic_concentration", "microplastics measurement", "measurement", "particles_per_liter", "pieces_per_litre", "value"))
  x <- dplyr::mutate(x, longitude = as_num(.data[[lon_col]]), latitude = as_num(.data[[lat_col]]), concentration = as_num(.data[[conc_col]]))
  raw <- nrow(x); bad_xy <- !valid_coordinates(x$longitude, x$latitude); outside <- !bad_xy & !in_study_area(x$longitude, x$latitude, cfg); missing_conc <- is.na(x$concentration); invalid_conc <- !missing_conc & x$concentration < 0
  keep <- !(bad_xy | outside | missing_conc | invalid_conc); candidates <- x[keep, , drop = FALSE]; clean <- dplyr::distinct(candidates, longitude, latitude, concentration, .keep_all = TRUE)
  audit <- tibble::tibble(dataset = "microplastics", raw_records = raw, invalid_coordinates = sum(bad_xy), outside_study_area = sum(outside), missing_concentration = sum(missing_conc), invalid_concentration = sum(invalid_conc), duplicates_removed = nrow(candidates) - nrow(clean), remaining_records = nrow(clean))
  if (!nrow(clean)) stop("No valid microplastic records remain inside the Indian Ocean study area.", call. = FALSE)
  list(data = sf::st_as_sf(clean, coords = c("longitude", "latitude"), crs = cfg$crs, remove = FALSE), audit = audit)
}

read_biodiversity <- function(path, cfg) {
  x <- readr::read_csv(path, show_col_types = FALSE, name_repair = "unique")
  lon_col <- pick_col(x, c("decimalLongitude", "longitude", "lon")); lat_col <- pick_col(x, c("decimalLatitude", "latitude", "lat")); species_col <- pick_col(x, c("scientificName", "scientific_name", "species")); group_col <- pick_col(x, c("phylum", "class", "taxonomic_group"), required = FALSE)
  taxonomic_group <- if (is.na(group_col)) rep(NA_character_, nrow(x)) else stringr::str_squish(as.character(x[[group_col]]))
  x <- dplyr::mutate(x, longitude = as_num(.data[[lon_col]]), latitude = as_num(.data[[lat_col]]), scientific_name = stringr::str_squish(as.character(.data[[species_col]])), taxonomic_group = taxonomic_group)
  raw <- nrow(x); bad_xy <- !valid_coordinates(x$longitude, x$latitude); outside <- !bad_xy & !in_study_area(x$longitude, x$latitude, cfg); no_species <- is.na(x$scientific_name) | x$scientific_name == ""
  keep <- !(bad_xy | outside | no_species); candidates <- x[keep, , drop = FALSE]; clean <- dplyr::distinct(candidates, longitude, latitude, scientific_name, .keep_all = TRUE)
  audit <- tibble::tibble(dataset = "biodiversity", raw_records = raw, invalid_coordinates = sum(bad_xy), outside_study_area = sum(outside), missing_species_identity = sum(no_species), duplicates_removed = nrow(candidates) - nrow(clean), remaining_records = nrow(clean))
  if (!nrow(clean)) stop("No valid biodiversity records remain inside the Indian Ocean study area.", call. = FALSE)
  list(data = sf::st_as_sf(clean, coords = c("longitude", "latitude"), crs = cfg$crs, remove = FALSE), audit = audit)
}

aggregate_grid <- function(mp_joined, bio_joined, grid) {
  pm <- mp_joined |> sf::st_drop_geometry() |> dplyr::filter(!is.na(cell_id)) |> dplyr::group_by(cell_id) |> dplyr::summarise(mean_microplastic = mean(concentration), median_microplastic = stats::median(concentration), p95_microplastic = stats::quantile(concentration, .95, names = FALSE), microplastic_sample_count = dplyr::n(), .groups = "drop")
  bm <- bio_joined |> sf::st_drop_geometry() |> dplyr::filter(!is.na(cell_id)) |> dplyr::group_by(cell_id) |> dplyr::summarise(species_richness = dplyr::n_distinct(scientific_name), taxonomic_group_richness = if (all(is.na(taxonomic_group) | taxonomic_group == "")) NA_integer_ else dplyr::n_distinct(taxonomic_group[!is.na(taxonomic_group) & taxonomic_group != ""], na.rm = TRUE), biodiversity_occurrence_count = dplyr::n(), .groups = "drop")
  grid |> dplyr::left_join(pm, by = "cell_id") |> dplyr::left_join(bm, by = "cell_id")
}

score_hotspots <- function(grid, threshold = .8) {
  if (threshold <= 0 || threshold >= 1) stop("Hotspot threshold must be strictly between 0 and 1.", call. = FALSE)
  grid |> dplyr::mutate(P = normalise_rank(mean_microplastic), B = normalise_rank(species_richness), hotspot_score = P * B, pollution_hotspot = quantile_flag(mean_microplastic, threshold), biodiversity_hotspot = quantile_flag(species_richness, threshold), effective_hotspot = dplyr::if_else(!is.na(pollution_hotspot) & !is.na(biodiversity_hotspot), pollution_hotspot & biodiversity_hotspot, NA), rank = dplyr::if_else(!is.na(hotspot_score), dplyr::min_rank(dplyr::desc(hotspot_score)), NA_integer_))
}

run_spatial_statistics <- function(grid, cfg) {
  valid <- grid |> dplyr::filter(!is.na(hotspot_score)); insufficient <- function(reason) list(moran = tibble::tibble(status = reason), gi = tibble::tibble(status = reason), clusters = tibble::tibble(status = reason))
  if (nrow(valid) < 4 || length(unique(valid$hotspot_score)) < 2) return(insufficient("insufficient variation or valid cells"))
  nb <- spdep::poly2nb(valid, queen = TRUE); if (!any(spdep::card(nb) > 0)) return(insufficient("no neighbouring valid cells"))
  lw <- spdep::nb2listw(nb, style = "W", zero.policy = TRUE); mi <- tryCatch(spdep::moran.test(valid$hotspot_score, lw, zero.policy = TRUE), error = function(e) NULL)
  if (is.null(mi)) return(insufficient("Moran's I could not be calculated"))
  gi <- tryCatch(spdep::localG(valid$hotspot_score, spdep::nb2listw(spdep::include.self(nb), style = "B", zero.policy = TRUE), zero.policy = TRUE), error = function(e) rep(NA_real_, nrow(valid)))
  pvals <- 2 * stats::pnorm(abs(as.numeric(gi)), lower.tail = FALSE); high <- valid |> dplyr::filter(hotspot_score >= stats::quantile(hotspot_score, cfg$hotspot_percentile, names = FALSE)); xy <- sf::st_coordinates(sf::st_centroid(sf::st_transform(high, 3857)))
  clusters <- if (nrow(high) >= cfg$dbscan_min_pts) dbscan::dbscan(xy, eps = cfg$dbscan_eps_km * 1000, minPts = cfg$dbscan_min_pts)$cluster else rep(NA_integer_, nrow(high))
  list(moran = tibble::tibble(status = "calculated", moran_i = unname(mi$estimate[[1]]), expected_i = unname(mi$estimate[[2]]), variance = unname(mi$estimate[[3]]), p_value = mi$p.value, valid_cells = nrow(valid)), gi = tibble::tibble(cell_id = valid$cell_id, gi_star_z = as.numeric(gi), p_value = pvals, p_value_bh = stats::p.adjust(pvals, method = "BH"), significant_high_cluster = as.numeric(gi) > 0 & stats::p.adjust(pvals, method = "BH") < .05), clusters = tibble::tibble(cell_id = high$cell_id, dbscan_cluster = clusters))
}

save_map <- function(grid, variable, title, file) {
  p <- ggplot2::ggplot(grid) + ggplot2::geom_sf(ggplot2::aes(fill = .data[[variable]]), colour = NA) + ggplot2::scale_fill_viridis_c(na.value = "grey90") + ggplot2::labs(title = title, fill = variable, x = "Longitude", y = "Latitude") + ggplot2::coord_sf(expand = FALSE) + ggplot2::theme_minimal(base_size = 12)
  ggplot2::ggsave(file, p, width = 12, height = 7, dpi = 300)
}

save_flag_map <- function(grid, variable, title, file) {
  x <- grid |> dplyr::mutate(.flag = dplyr::case_when(is.na(.data[[variable]]) ~ "No paired observation", .data[[variable]] ~ "Hotspot", TRUE ~ "Not hotspot"))
  p <- ggplot2::ggplot(x) + ggplot2::geom_sf(ggplot2::aes(fill = .flag), colour = NA) + ggplot2::scale_fill_manual(values = c("Hotspot" = "#b2182b", "Not hotspot" = "#d1e5f0", "No paired observation" = "grey90")) + ggplot2::labs(title = title, fill = NULL, x = "Longitude", y = "Latitude") + ggplot2::coord_sf(expand = FALSE) + ggplot2::theme_minimal(base_size = 12)
  ggplot2::ggsave(file, p, width = 12, height = 7, dpi = 300)
}
