# ============================================================
# STEP 11 - MAPS, FIGURES, SUMMARY TABLES AND THE REPORT
# ============================================================
# WHAT THIS STEP DOES
#   This is the final step. It produces everything a reader actually looks at.
#
#   A. TEN MAPS
#      2 observation-location maps, then for each layer:
#        continuous value + yes/no hotspot + the combined score
#      1 map of the DBSCAN priority clusters
#
#   B. FIVE SUPPORTING FIGURES
#      distribution charts and, importantly, three EFFORT charts that test
#      whether our hotspots are just artefacts of where people sampled more
#
#   C. TWO SUMMARY FILES
#      analysis_summary.csv   - headline counts
#      results_report.md      - the written results report
#
# WHY SO MANY MAPS?
#   Each map answers one question:
#     where were samples taken?          -> shows sampling bias honestly
#     where is pollution highest?        -> the pollution layer
#     where is richness highest?         -> the biodiversity layer
#     which cells are hot on each?       -> the threshold labels
#     which cells are hot on BOTH?       -> the actual research answer
#
# WHY THE "SAMPLING EFFORT" FIGURES MATTER MOST
#   High recorded richness can simply mean "more boats went there".
#   These scatter plots put effort on the x-axis and the result on the
#   y-axis. If richness rises steeply with effort, part of our biodiversity
#   hotspot pattern is sampling effort rather than real diversity, and the
#   report must say so. This is the honest way to handle the biggest
#   limitation of occurrence-based data.
# ============================================================


# ---- Set-up -----------------------------------------------------------------
source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()


# ---- Load everything we need -------------------------------------------------
grid_analysis   <- readRDS("data/processed/grid_analysis.rds")
mp              <- readRDS("data/interim/microplastics_clean.rds")
bio             <- readRDS("data/interim/biodiversity_clean.rds")


# ================================================================
# A. THE MAPS
# ================================================================

# ---- A1. A reusable helper for "where were the samples taken?" ---------------
# Defined as a function because we use it twice with different data.
# geom_sf() draws shapes; the first layer is a pale rectangle of the study
# area so the reader can see the boundary, and the second layer plots the
# points on top of it.
point_map <- function(points, title, file, colour) {

  p <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = study_area(cfg),
                     fill  = "#eaf3f8",
                     colour = "grey70") +
    ggplot2::geom_sf(data = points,
                     colour = colour,
                     alpha   = 0.65,   # semi-transparent so density is visible
                     size    = 0.8) +
    ggplot2::labs(title = title,
                  x = "Longitude",
                  y = "Latitude") +
    ggplot2::coord_sf(expand = FALSE) +   # no empty margin around the map
    ggplot2::theme_minimal(base_size = 12)

  ggplot2::ggsave(file, p, width = 12, height = 7, dpi = 300)
}

# Use it once for each dataset. Red = pollution, blue = biodiversity.
point_map(mp,  "Microplastic observation locations",
          "outputs/maps/microplastic_observation_locations.png", "#d7301f")

point_map(bio, "Biodiversity observation locations",
          "outputs/maps/biodiversity_observation_locations.png", "#225ea8")


# ---- A2. Continuous-variable maps -------------------------------------------
# save_map() is defined in utils.R. It is used for any numeric column.

# Average microplastic concentration per cell.
save_map(grid_analysis, "mean_microplastic",
         "Mean microplastic concentration by grid cell",
         "outputs/maps/mean_microplastic.png")

# Number of different species recorded per cell.
save_map(grid_analysis, "species_richness",
         "Observed species richness by grid cell",
         "outputs/maps/species_richness.png")

# The combined priority score (P x B).
save_map(grid_analysis, "hotspot_score",
         "Pollution-biodiversity hotspot score",
         "outputs/maps/hotspot_score.png")


# ---- A3. Yes / No hotspot maps ----------------------------------------------
# save_flag_map() is defined in utils.R. It uses three colours and always
# keeps "no paired observation" (grey) separate from "not a hotspot" (blue).

save_flag_map(grid_analysis, "pollution_hotspot",
              "Pollution hotspots",
              "outputs/maps/pollution_hotspots.png")

save_flag_map(grid_analysis, "biodiversity_hotspot",
              "Biodiversity hotspots",
              "outputs/maps/biodiversity_hotspots.png")

# The key deliverable map: cells that are hot on BOTH layers.
save_flag_map(grid_analysis, "effective_hotspot",
              "Effective hotspots",
              "outputs/maps/effective_hotspots.png")


# ---- A4. DBSCAN cluster map --------------------------------------------------
# Read the cluster table produced in step 9.
cluster_table <- readr::read_csv("outputs/tables/dbscan_results.csv",
                                 show_col_types = FALSE)

# Attach the cluster number to each cell. If the file has no cell_id column
# (because DBSCAN could not run), we simply add a column of missing values
# instead of stopping.
cluster_grid <- if ("cell_id" %in% names(cluster_table)) {
  grid_analysis |> dplyr::left_join(cluster_table, by = "cell_id")
} else {
  grid_analysis |> dplyr::mutate(dbscan_cluster = NA_integer_)
}

# factor() is needed because cluster numbers are categories, not quantities.
p <- ggplot2::ggplot(cluster_grid) +
  ggplot2::geom_sf(ggplot2::aes(fill = factor(dbscan_cluster)), colour = NA) +
  ggplot2::scale_fill_discrete(na.value = "grey90") +
  ggplot2::labs(title = "DBSCAN clusters of high-priority cells",
                fill = "Cluster",
                x = "Longitude", y = "Latitude") +
  ggplot2::coord_sf(expand = FALSE) +
  ggplot2::theme_minimal(base_size = 12)

ggplot2::ggsave("outputs/maps/dbscan_priority_clusters.png",
                p, width = 12, height = 7, dpi = 300)


# ---- A5. Getis-Ord Gi* significance map ------------------------------------
# Gi* identifies cells that are part of a statistically significant
# high-value cluster after the Benjamini-Hochberg correction.
gi_table <- readr::read_csv(
  "outputs/tables/getis_ord_results.csv",
  show_col_types = FALSE
)

gi_grid <- grid_analysis |>
  dplyr::left_join(
    gi_table |>
      dplyr::select(
        cell_id,
        gi_star_z,
        p_value_bh,
        significant_high_cluster
      ),
    by = "cell_id"
  )

gi_plot <- ggplot2::ggplot(gi_grid) +
  ggplot2::geom_sf(
    ggplot2::aes(fill = significant_high_cluster),
    colour = NA
  ) +
  ggplot2::scale_fill_manual(
    values = c(
      "TRUE" = "#b2182b",
      "FALSE" = "#d1e5f0"
    ),
    na.value = "grey90"
  ) +
  ggplot2::labs(
    title = "Statistically significant Gi* high-value clusters",
    fill = "Significant high cluster",
    x = "Longitude",
    y = "Latitude"
  ) +
  ggplot2::coord_sf(expand = FALSE) +
  ggplot2::theme_minimal(base_size = 12)

ggplot2::ggsave(
  "outputs/maps/gi_star_high_clusters.png",
  gi_plot,
  width = 12,
  height = 7,
  dpi = 300
)


# ================================================================
# B. SUPPORTING FIGURES
# ================================================================

# ---- B1. Distribution of the hotspot score -----------------------------------
# Only cells that have a score are plotted (na.rm = TRUE inside the geom).
fig <- ggplot2::ggplot(sf::st_drop_geometry(grid_analysis),
                       ggplot2::aes(hotspot_score)) +
  ggplot2::geom_histogram(bins = 30, fill = "#8856a7", colour = "white") +
  ggplot2::labs(title = "Hotspot score distribution",
                x = "P x B score",
                y = "Grid cells") +
  ggplot2::theme_minimal()

ggplot2::ggsave("outputs/figures/hotspot_score_distribution.png",
                fig, width = 8, height = 5, dpi = 300)


# ---- B2. Sampling-effort checks ----------------------------------------------
# Take only the cells that have BOTH layers, because those are the cells the
# hotspot score was computed from.
paired_cells <- sf::st_drop_geometry(grid_analysis) |>
  dplyr::filter(!is.na(hotspot_score))

# We need at least two cells to draw a scatter plot, so we guard the whole
# block with a single if().
if (nrow(paired_cells) > 1) {

  # --- Effort vs species richness --------------------------------------------
  # If this looks like a rising cloud, richness partly reflects effort.
  p <- ggplot2::ggplot(paired_cells,
                       ggplot2::aes(x = biodiversity_occurrence_count,
                                    y = species_richness)) +
    ggplot2::geom_point(alpha = 0.7) +
    ggplot2::labs(title = "Species richness and sampling effort",
                  x = "Biodiversity occurrence count",
                  y = "Species richness") +
    ggplot2::theme_minimal()

  ggplot2::ggsave("outputs/figures/richness_vs_sampling_effort.png",
                  p, width = 7, height = 5, dpi = 300)

  # --- Effort vs pollution ----------------------------------------------------
  # Same idea for the pollution layer.
  p <- ggplot2::ggplot(paired_cells,
                       ggplot2::aes(x = microplastic_sample_count,
                                    y = mean_microplastic)) +
    ggplot2::geom_point(alpha = 0.7) +
    ggplot2::labs(title = "Microplastic concentration and sampling effort",
                  x = "Microplastic sample count",
                  y = "Mean microplastic concentration") +
    ggplot2::theme_minimal()

  ggplot2::ggsave("outputs/figures/pollution_vs_sampling_effort.png",
                  p, width = 7, height = 5, dpi = 300)

  # --- Combined effort vs the final score ------------------------------------
  # The most important check of the three: does our priority score simply
  # track how many samples a cell received?
  p <- ggplot2::ggplot(paired_cells,
                       ggplot2::aes(x = microplastic_sample_count +
                                         biodiversity_occurrence_count,
                                    y = hotspot_score)) +
    ggplot2::geom_point(alpha = 0.7) +
    ggplot2::labs(title = "Hotspot score and combined sampling density",
                  x = "Microplastic samples + biodiversity occurrences",
                  y = "Hotspot score") +
    ggplot2::theme_minimal()

  ggplot2::ggsave("outputs/figures/hotspot_score_vs_sampling_density.png",
                  p, width = 7, height = 5, dpi = 300)
}


# ================================================================
# C. SUMMARY TABLE AND WRITTEN REPORT
# ================================================================

# ---- C1. Headline numbers ----------------------------------------------------
# sum(x, na.rm = TRUE) counts the TRUE values while ignoring the NA cells.
# NA cells are excluded rather than counted as FALSE, because "we have no
# data here" and "this cell is not a hotspot" are different statements.
analysis_summary <- sf::st_drop_geometry(grid_analysis) |>
  dplyr::summarise(
    grid_cells           = dplyr::n(),
    valid_paired_cells   = sum(!is.na(hotspot_score)),
    pollution_hotspots   = sum(pollution_hotspot,   na.rm = TRUE),
    biodiversity_hotspots = sum(biodiversity_hotspot, na.rm = TRUE),
    effective_hotspots   = sum(effective_hotspot,   na.rm = TRUE)
  )

readr::write_csv(analysis_summary, "outputs/tables/analysis_summary.csv")


# ---- C2. The written report --------------------------------------------------
# The report is built as a character VECTOR of lines, then written with
# writeLines(). paste0() glues a label and a number together, so the numbers
# come straight from the analysis instead of being typed by hand.
#
# The limitations paragraph is deliberately explicit, because stating the
# limits of the data is part of good scientific practice.
report <- c(
  "# Results report",
  "",
  "## Scope",
  paste("This report identifies observed overlap between reported microplastic",
        "concentration and observed species richness in a common Indian Ocean",
        "grid. It does not infer causality."),
  "",
  "## Dataset and grid summary",
  paste0("Grid cells: ", analysis_summary$grid_cells),
  paste0("Cells with both observation layers: ", analysis_summary$valid_paired_cells),
  "",
  "## Hotspot results",
  paste0("Pollution hotspots: ", analysis_summary$pollution_hotspots),
  paste0("Biodiversity hotspots: ", analysis_summary$biodiversity_hotspots),
  paste0("Effective hotspots: ", analysis_summary$effective_hotspots),
  "",
  "## Limitations",
  paste("Uneven sampling, temporal mismatch, heterogeneous microplastic methods,",
        "the chosen grid resolution, and occurrence-record bias can affect these",
        "observed patterns. Missing records remain missing; they are never",
        "treated as zero.")
)

writeLines(report, "outputs/results/results_report.md")