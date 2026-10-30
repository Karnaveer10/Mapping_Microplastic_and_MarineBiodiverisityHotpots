# Shared helper functions for the marine microplastic analysis.

# Packages used by the project. Install them with scripts/setup_packages.R.
required_packages <- c(
  "sf", "dplyr", "readr", "ggplot2", "tidyr", "stringr",
  "spdep", "dbscan", "scales", "purrr", "tibble"
)

project_library <- "renv/library/R-4.6"

configure_project_library <- function() {
  if (dir.exists(project_library)) {
    .libPaths(c(normalizePath(project_library), .libPaths()))
  }

  invisible(.libPaths())
}

configure_project_library()

load_project_packages <- function() {
  configure_project_library()

  missing <- required_packages[
    !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
  ]

  if (length(missing) > 0) {
    stop(
      "Install required R packages before running: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  invisible(lapply(required_packages, library, character.only = TRUE))
}

ensure_dirs <- function() {
  folders <- c(
    "data/raw",
    "data/interim",
    "data/processed",
    "outputs/figures",
    "outputs/maps",
    "outputs/tables",
    "outputs/results"
  )

  invisible(lapply(
    folders,
    dir.create,
    recursive = TRUE,
    showWarnings = FALSE
  ))
}


# Basic data helpers -----------------------------------------------------------

study_area <- function(cfg) {
  bbox <- sf::st_bbox(cfg$study_bbox, crs = sf::st_crs(cfg$crs))
  sf::st_as_sfc(bbox)
}

pick_col <- function(data, choices, required = TRUE) {
  names_lower <- tolower(names(data))
  matches <- choices[tolower(choices) %in% names_lower]

  if (length(matches) == 0) {
    if (required) {
      stop(
        "Required column absent. Expected one of: ",
        paste(choices, collapse = ", "),
        call. = FALSE
      )
    }

    return(NA_character_)
  }

  names(data)[match(tolower(matches[[1]]), names_lower)]
}

as_num <- function(x) {
  suppressWarnings(readr::parse_number(as.character(x)))
}

valid_coordinates <- function(lon, lat) {
  !is.na(lon) &
    !is.na(lat) &
    lon >= -180 & lon <= 180 &
    lat >= -90 & lat <= 90
}

in_study_area <- function(lon, lat, cfg) {
  lon >= cfg$study_bbox[["xmin"]] &
    lon <= cfg$study_bbox[["xmax"]] &
    lat >= cfg$study_bbox[["ymin"]] &
    lat <= cfg$study_bbox[["ymax"]]
}


# Scores and flags -------------------------------------------------------------

normalise_rank <- function(x) {
  result <- rep(NA_real_, length(x))
  known <- !is.na(x)

  if (sum(known) == 1L) {
    result[known] <- 1
  } else if (sum(known) > 1L) {
    result[known] <- dplyr::percent_rank(x[known])
  }

  result
}

quantile_flag <- function(x, threshold, subset_indices = NULL) {
  result <- rep(NA, length(x))
  known <- !is.na(x)

  if (is.null(subset_indices)) {
    cutoff_values <- known
  } else {
    cutoff_values <- known & subset_indices
  }

  if (!any(cutoff_values)) {
    return(result)
  }

  cutoff <- stats::quantile(
    x[cutoff_values],
    threshold,
    names = FALSE,
    type = 7
  )

  result[known] <- x[known] > cutoff
  result
}


# Grid and spatial joins ------------------------------------------------------

make_grid <- function(cfg, resolution = cfg$grid_degrees) {
  if (!resolution %in% c(0.5, 1.0)) {
    stop("Grid resolution must be 0.5 or 1.0 degrees.", call. = FALSE)
  }

  grid <- sf::st_make_grid(
    study_area(cfg),
    cellsize = c(resolution, resolution),
    square = TRUE,
    what = "polygons"
  )
  grid <- sf::st_sf(geometry = grid)

  centres <- sf::st_coordinates(sf::st_centroid(grid))
  xmin <- cfg$study_bbox[["xmin"]]
  ymin <- cfg$study_bbox[["ymin"]]

  west <- floor((centres[, 1] - xmin) / resolution) * resolution + xmin
  south <- floor((centres[, 2] - ymin) / resolution) * resolution + ymin

  grid$cell_id <- sprintf("IO_%0.1f_%0.1f", west, south)
  dplyr::select(grid, cell_id, geometry)
}

assign_cells <- function(points, grid) {
  matches <- sf::st_intersects(points, grid)

  cell_id <- vapply(
    matches,
    function(index) {
      if (length(index) == 0) {
        NA_character_
      } else {
        grid$cell_id[[index[[1]]]]
      }
    },
    character(1)
  )

  points$cell_id <- cell_id

  list(
    data = points,
    assigned = sum(!is.na(cell_id)),
    unassigned = sum(is.na(cell_id))
  )
}


# Reading and cleaning ---------------------------------------------------------

read_microplastics <- function(path, cfg) {
  data <- readr::read_csv(
    path,
    show_col_types = FALSE,
    name_repair = "unique"
  )

  longitude_col <- pick_col(
    data,
    c("longitude", "lon", "decimalLongitude",
      "longitude (degree)", "longitude(degree)")
  )
  latitude_col <- pick_col(
    data,
    c("latitude", "lat", "decimalLatitude",
      "latitude (degree)", "latitude(degree)")
  )
  concentration_col <- pick_col(
    data,
    c("concentration", "microplastic_concentration",
      "microplastics measurement", "measurement",
      "particles_per_liter", "pieces_per_litre", "value")
  )

  data <- dplyr::mutate(
    data,
    longitude = as_num(.data[[longitude_col]]),
    latitude = as_num(.data[[latitude_col]]),
    concentration = as_num(.data[[concentration_col]])
  )

  raw_records <- nrow(data)
  invalid_coordinates <- !valid_coordinates(data$longitude, data$latitude)
  outside_study_area <- !invalid_coordinates &
    !in_study_area(data$longitude, data$latitude, cfg)
  missing_concentration <- is.na(data$concentration)
  invalid_concentration <- !missing_concentration & data$concentration < 0

  keep <- !(
    invalid_coordinates |
      outside_study_area |
      missing_concentration |
      invalid_concentration
  )

  candidates <- data[keep, , drop = FALSE]
  clean <- dplyr::distinct(
    candidates,
    longitude,
    latitude,
    concentration,
    .keep_all = TRUE
  )

  audit <- tibble::tibble(
    dataset = "microplastics",
    raw_records = raw_records,
    invalid_coordinates = sum(invalid_coordinates),
    outside_study_area = sum(outside_study_area),
    missing_concentration = sum(missing_concentration),
    invalid_concentration = sum(invalid_concentration),
    duplicates_removed = nrow(candidates) - nrow(clean),
    remaining_records = nrow(clean)
  )

  if (nrow(clean) == 0) {
    stop(
      "No valid microplastic records remain inside the Indian Ocean study area.",
      call. = FALSE
    )
  }

  list(
    data = sf::st_as_sf(
      clean,
      coords = c("longitude", "latitude"),
      crs = cfg$crs,
      remove = FALSE
    ),
    audit = audit
  )
}

read_biodiversity <- function(path, cfg) {
  data <- readr::read_csv(
    path,
    show_col_types = FALSE,
    name_repair = "unique"
  )

  longitude_col <- pick_col(data, c("decimalLongitude", "longitude", "lon"))
  latitude_col <- pick_col(data, c("decimalLatitude", "latitude", "lat"))
  species_col <- pick_col(
    data,
    c("scientificName", "scientific_name", "species")
  )
  group_col <- pick_col(
    data,
    c("phylum", "class", "taxonomic_group"),
    required = FALSE
  )

  if (is.na(group_col)) {
    taxonomic_group <- rep(NA_character_, nrow(data))
  } else {
    taxonomic_group <- stringr::str_squish(as.character(data[[group_col]]))
  }

  data <- dplyr::mutate(
    data,
    longitude = as_num(.data[[longitude_col]]),
    latitude = as_num(.data[[latitude_col]]),
    scientific_name = stringr::str_squish(
      as.character(.data[[species_col]])
    ),
    taxonomic_group = taxonomic_group
  )

  raw_records <- nrow(data)
  invalid_coordinates <- !valid_coordinates(data$longitude, data$latitude)
  outside_study_area <- !invalid_coordinates &
    !in_study_area(data$longitude, data$latitude, cfg)
  missing_species <- is.na(data$scientific_name) | data$scientific_name == ""

  keep <- !(invalid_coordinates | outside_study_area | missing_species)
  candidates <- data[keep, , drop = FALSE]
  clean <- dplyr::distinct(
    candidates,
    longitude,
    latitude,
    scientific_name,
    .keep_all = TRUE
  )

  audit <- tibble::tibble(
    dataset = "biodiversity",
    raw_records = raw_records,
    invalid_coordinates = sum(invalid_coordinates),
    outside_study_area = sum(outside_study_area),
    missing_species_identity = sum(missing_species),
    duplicates_removed = nrow(candidates) - nrow(clean),
    remaining_records = nrow(clean)
  )

  if (nrow(clean) == 0) {
    stop(
      "No valid biodiversity records remain inside the Indian Ocean study area.",
      call. = FALSE
    )
  }

  list(
    data = sf::st_as_sf(
      clean,
      coords = c("longitude", "latitude"),
      crs = cfg$crs,
      remove = FALSE
    ),
    audit = audit
  )
}


# Grid summaries and hotspot scores -------------------------------------------

aggregate_grid <- function(mp_joined, bio_joined, grid) {
  microplastics <- mp_joined |>
    sf::st_drop_geometry() |>
    dplyr::filter(!is.na(cell_id)) |>
    dplyr::group_by(cell_id) |>
    dplyr::summarise(
      mean_microplastic = mean(concentration),
      median_microplastic = stats::median(concentration),
      p95_microplastic = stats::quantile(
        concentration,
        0.95,
        names = FALSE
      ),
      microplastic_sample_count = dplyr::n(),
      .groups = "drop"
    )

  biodiversity <- bio_joined |>
    sf::st_drop_geometry() |>
    dplyr::filter(!is.na(cell_id)) |>
    dplyr::group_by(cell_id) |>
    dplyr::summarise(
      species_richness = dplyr::n_distinct(scientific_name),
      taxonomic_group_richness = if (
        all(is.na(taxonomic_group) | taxonomic_group == "")
      ) {
        NA_integer_
      } else {
        dplyr::n_distinct(
          taxonomic_group[
            !is.na(taxonomic_group) & taxonomic_group != ""
          ]
        )
      },
      biodiversity_occurrence_count = dplyr::n(),
      .groups = "drop"
    )

  grid |>
    dplyr::left_join(microplastics, by = "cell_id") |>
    dplyr::left_join(biodiversity, by = "cell_id")
}

score_hotspots <- function(
  grid,
  threshold = 0.8,
  domain = "all_observed"
) {
  if (threshold <= 0 || threshold >= 1) {
    stop(
      "Hotspot threshold must be strictly between 0 and 1.",
      call. = FALSE
    )
  }

  if (domain == "co_sampled") {
    subset_indices <- !is.na(grid$mean_microplastic) &
      !is.na(grid$species_richness)
  } else {
    subset_indices <- NULL
  }

  grid |>
    dplyr::mutate(
      P = normalise_rank(mean_microplastic),
      B = normalise_rank(species_richness),
      hotspot_score = P * B,
      pollution_hotspot = quantile_flag(
        mean_microplastic,
        threshold,
        subset_indices
      ),
      biodiversity_hotspot = quantile_flag(
        species_richness,
        threshold,
        subset_indices
      ),
      effective_hotspot = dplyr::if_else(
        !is.na(pollution_hotspot) & !is.na(biodiversity_hotspot),
        pollution_hotspot & biodiversity_hotspot,
        NA
      ),
      rank = dplyr::if_else(
        !is.na(hotspot_score),
        dplyr::min_rank(dplyr::desc(hotspot_score)),
        NA_integer_
      )
    )
}


# Spatial statistics -----------------------------------------------------------

run_spatial_statistics <- function(grid, cfg) {
  valid <- dplyr::filter(grid, !is.na(hotspot_score))

  insufficient <- function(reason) {
    list(
      moran = tibble::tibble(status = reason),
      gi = tibble::tibble(status = reason),
      clusters = tibble::tibble(status = reason)
    )
  }

  if (
    nrow(valid) < 4 ||
      length(unique(valid$hotspot_score)) < 2
  ) {
    return(insufficient("insufficient variation or valid cells"))
  }

  neighbours <- spdep::poly2nb(valid, queen = TRUE)

  if (!any(spdep::card(neighbours) > 0)) {
    return(insufficient("no neighbouring valid cells"))
  }

  weights <- spdep::nb2listw(
    neighbours,
    style = "W",
    zero.policy = TRUE
  )

  moran <- tryCatch(
    spdep::moran.test(
      valid$hotspot_score,
      weights,
      zero.policy = TRUE
    ),
    error = function(error) NULL
  )

  if (is.null(moran)) {
    return(insufficient("Moran's I could not be calculated"))
  }

  gi_values <- tryCatch(
    spdep::localG(
      valid$hotspot_score,
      spdep::nb2listw(
        spdep::include.self(neighbours),
        style = "B",
        zero.policy = TRUE
      ),
      zero.policy = TRUE
    ),
    error = function(error) rep(NA_real_, nrow(valid))
  )

  gi_values <- as.numeric(gi_values)
  p_values <- 2 * stats::pnorm(abs(gi_values), lower.tail = FALSE)
  adjusted_p_values <- stats::p.adjust(p_values, method = "BH")

  high_score <- stats::quantile(
    valid$hotspot_score,
    cfg$hotspot_percentile,
    names = FALSE
  )
  high <- dplyr::filter(valid, hotspot_score >= high_score)

  coordinates <- sf::st_coordinates(
    sf::st_centroid(sf::st_transform(high, 3857))
  )

  if (nrow(high) >= cfg$dbscan_min_pts) {
    clusters <- dbscan::dbscan(
      coordinates,
      eps = cfg$dbscan_eps_km * 1000,
      minPts = cfg$dbscan_min_pts
    )$cluster
  } else {
    clusters <- rep(NA_integer_, nrow(high))
  }

  list(
    moran = tibble::tibble(
      status = "calculated",
      moran_i = unname(moran$estimate[[1]]),
      expected_i = unname(moran$estimate[[2]]),
      variance = unname(moran$estimate[[3]]),
      p_value = moran$p.value,
      valid_cells = nrow(valid)
    ),
    gi = tibble::tibble(
      cell_id = valid$cell_id,
      gi_star_z = gi_values,
      p_value = p_values,
      p_value_bh = adjusted_p_values,
      significant_high_cluster = gi_values > 0 & adjusted_p_values < 0.05
    ),
    clusters = tibble::tibble(
      cell_id = high$cell_id,
      dbscan_cluster = clusters
    )
  )
}


# Plot helpers -----------------------------------------------------------------

save_map <- function(grid, variable, title, file) {
  plot <- ggplot2::ggplot(grid) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = .data[[variable]]),
      colour = NA
    ) +
    ggplot2::scale_fill_viridis_c(na.value = "grey90") +
    ggplot2::labs(
      title = title,
      fill = variable,
      x = "Longitude",
      y = "Latitude"
    ) +
    ggplot2::coord_sf(expand = FALSE) +
    ggplot2::theme_minimal(base_size = 12)

  ggplot2::ggsave(file, plot, width = 12, height = 7, dpi = 300)
}

save_flag_map <- function(grid, variable, title, file) {
  data <- dplyr::mutate(
    grid,
    .flag = dplyr::case_when(
      is.na(.data[[variable]]) ~ "No paired observation",
      .data[[variable]] ~ "Hotspot",
      TRUE ~ "Not hotspot"
    )
  )

  plot <- ggplot2::ggplot(data) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = .flag),
      colour = NA
    ) +
    ggplot2::scale_fill_manual(
      values = c(
        "Hotspot" = "#b2182b",
        "Not hotspot" = "#d1e5f0",
        "No paired observation" = "grey90"
      )
    ) +
    ggplot2::labs(
      title = title,
      fill = NULL,
      x = "Longitude",
      y = "Latitude"
    ) +
    ggplot2::coord_sf(expand = FALSE) +
    ggplot2::theme_minimal(base_size = 12)

  ggplot2::ggsave(file, plot, width = 12, height = 7, dpi = 300)
}
