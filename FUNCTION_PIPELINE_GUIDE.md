# Pipeline Function Execution & Code Guide

A chronological reference explaining every function in `R/utils.R`, how they flow through the pipeline, and the exact code implementation of `R/10_sensitivity_analysis.R` and `R/11_visualization.R`. Designed for presentations, vivas, and project defense.

---

## 1. Chronological Function Call Sequence

The master runner (`scripts/run_pipeline.R`) calls each script in numeric order. Below is the chronological order of every function called from `R/utils.R`:

| Order | Pipeline Step | Function in `R/utils.R` | Plain-English Explanation (For Teachers / Examiners) |
| :---: | :--- | :--- | :--- |
| **0.1** | *Global Setup* | `configure_project_library()` | Directs R to use the local `renv` library first, guaranteeing exact package versions and reproducibility. |
| **0.2** | *Global Setup* | `load_project_packages()` | Checks that all 11 required libraries (`sf`, `dplyr`, `readr`, `ggplot2`, `spdep`, etc.) exist, then attaches them. |
| **0.3** | *Global Setup* | `ensure_dirs()` | Creates all input/output directories (`data/interim`, `data/processed`, `outputs/maps`, etc.) if they do not exist. |
| **1** | `01_download_data.R` | *(Built-in tibble & CSV writers)* | Creates `source_metadata.csv` and `DATA_DICTIONARY.csv` before running analysis to record full data provenance. |
| **2** | `02_clean_microplastics.R` | `read_microplastics(path, cfg)` | Reads the raw stressor/pollution CSV, runs 4 data validation checks, and saves a cleaned spatial points object (`.rds`). |
| **2.1** | *(Inside `read_microplastics`)* | `pick_col(x, choices)` | Finds a required column from multiple possible header spellings (e.g., `"longitude"` vs `"lon"` vs `"decimalLongitude"`). |
| **2.2** | *(Inside `read_microplastics`)* | `as_num(x)` | Safely extracts numeric data from text strings while stripping trailing unit text. |
| **2.3** | *(Inside `read_microplastics`)* | `valid_coordinates(lon, lat)` | Filters coordinates to ensure longitude is $-180\dots180$ and latitude is $-90\dots90$. |
| **2.4** | *(Inside `read_microplastics`)* | `in_study_area(lon, lat, cfg)`| Restricts coordinates to our Indian Ocean study box ($20^\circ\text{E}–147^\circ\text{E}, 60^\circ\text{S}–30^\circ\text{N}$). |
| **3** | `03_clean_biodiversity.R` | `read_biodiversity(path, cfg)` | Reads and cleans the 1.14 GB OBIS species file, eliminating bad coordinates, blanks, and duplicates. |
| **4** | `04_create_grid.R` | `make_grid(cfg, resolution)` | Chops the bounding box into uniform $0.5^\circ \times 0.5^\circ$ polygon cells and assigns readable IDs (e.g., `IO_73.5_15.5`). |
| **4.1** | *(Inside `make_grid`)* | `study_area(cfg)` | Converts the 4 bounding coordinates from `config.R` into an `sf` polygon rectangle. |
| **5** | `05_spatial_join.R` | `assign_cells(points, grid)` | Performs spatial intersection (`st_intersects`), tagging each point with the `cell_id` of the polygon it falls inside. |
| **6** | `06_pollution_analysis.R` | *(EDA summaries & histograms)* | Computes quartiles/summary statistics and plots raw vs. log-transformed frequency histograms. |
| **7** | `07_biodiversity_analysis.R` | *(EDA summaries & species barplot)*| Computes species richness vs. occurrence ratios and generates the Top 20 most recorded species chart. |
| **8** | `08_hotspot_analysis.R` | `aggregate_grid(mp, bio, grid)` | Aggregates points per grid cell: computes mean/median/p95 for stressor, and distinct species count for richness. |
| **8.1** | `08_hotspot_analysis.R` | `score_hotspots(grid, threshold, domain)` | Normalizes both metrics ($P, B \in [0, 1]$), computes priority score ($P \times B$), and flags hotspots. |
| **8.2** | *(Inside `score_hotspots`)* | `normalise_rank(x)` | Scales metrics to $0\dots1$ via `percent_rank` so different units (concentration vs. species count) can be multiplied. |
| **8.3** | *(Inside `score_hotspots`)* | `quantile_flag(x, threshold, subset)` | Flags values above the cut-off percentile (e.g. top 20%). Supports subdomain filtering to avoid sample-size imbalance. |
| **9** | `09_spatial_statistics.R` | `run_spatial_statistics(grid, cfg)` | Evaluates spatial autocorrelation: calculates global Moran's I, local Getis-Ord Gi* z-scores, and DBSCAN clusters. |
| **10** | `10_sensitivity_analysis.R` | *Re-runs pipeline across 6 settings* | Validates robustness across 3 thresholds (0.70, 0.80, 0.90) and 2 grid sizes (0.5°, 1.0°). |
| **11** | `11_visualization.R` | `point_map()`, `save_map()`, `save_flag_map()` | Draws 10 publication-ready maps, 3 sampling effort scatter plots, and writes `results_report.md`. |

---

## 2. Step 10: Sensitivity Analysis (`R/10_sensitivity_analysis.R`)

### Viva / Defense Explanation
> *"A common critique of hotspot mapping is that choosing an 80th percentile threshold or a 0.5° cell size is arbitrary. Step 10 answers this question with evidence: it re-runs the entire pipeline across 6 combinations (3 thresholds × 2 resolutions) using functional programming (`purrr::map2`). By demonstrating that the primary hotspots remain consistent across settings, we prove our conclusions are robust."*

### Chronological Functions Called in Step 10
1. `make_grid(cfg, resolution)`: Builds the grid at 0.5° or 1.0°.
2. `assign_cells(mp, grid)` & `assign_cells(bio, grid)`: Matches observations to the newly generated grid cells.
3. `aggregate_grid(mpj, bioj, grid)`: Summarizes points into mean stressor and species richness per cell.
4. `score_hotspots(..., threshold, domain)`: Evaluates hotspot labels for the given percentile (0.70, 0.80, 0.90).
5. `ggplot2::geom_col()`: Draws sensitivity comparison charts by threshold and resolution.

### Complete Code
```r
# ============================================================
# STEP 10 - SENSITIVITY ANALYSIS
# ============================================================
source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()

# Load cleaned points once (they do not change)
mp  <- readRDS("data/interim/microplastics_clean.rds")
bio <- readRDS("data/interim/biodiversity_clean.rds")

# Run all 6 combinations (2 resolutions x 3 thresholds)
results <- tidyr::crossing(
  grid_degrees = cfg$sensitivity_resolutions,   # c(0.5, 1.0)
  threshold    = cfg$sensitivity_thresholds     # c(0.70, 0.80, 0.90)
) |>
  dplyr::mutate(
    result = purrr::map2(grid_degrees, threshold,
                         function(resolution, threshold) {
                           # 1. Rebuild the grid at this resolution
                           grid <- make_grid(cfg, resolution)

                           # 2. Put both datasets into that grid
                           mpj  <- assign_cells(mp,  grid)$data
                           bioj <- assign_cells(bio, grid)$data

                           # 3. Summarise, then score with this threshold
                           x <- score_hotspots(
                                  aggregate_grid(mpj, bioj, grid),
                                  threshold,
                                  domain = cfg$hotspot_domain)

                           # 4. Return headline counts
                           tibble::tibble(
                             valid_paired_cells   = sum(!is.na(x$hotspot_score)),
                             pollution_hotspots    = sum(x$pollution_hotspot,   na.rm = TRUE),
                             biodiversity_hotspots = sum(x$biodiversity_hotspot, na.rm = TRUE),
                             effective_hotspots    = sum(x$effective_hotspot,   na.rm = TRUE)
                           )
                         })
  ) |>
  tidyr::unnest(result)

# Save the sensitivity table
readr::write_csv(results, "outputs/tables/sensitivity_analysis.csv")

# Chart 1: Sensitivity by Threshold
p1 <- ggplot2::ggplot(results,
                      ggplot2::aes(x = factor(threshold),
                                   y = effective_hotspots,
                                   fill = factor(grid_degrees))) +
  ggplot2::geom_col(position = "dodge") +
  ggplot2::labs(title = "Effective hotspots by threshold and grid resolution",
                x = "Hotspot percentile",
                y = "Effective hotspots",
                fill = "Grid degrees") +
  ggplot2::theme_minimal()

ggplot2::ggsave("outputs/figures/sensitivity_thresholds.png",
                p1, width = 8, height = 5, dpi = 300)

# Chart 2: Sensitivity by Grid Resolution
p2 <- ggplot2::ggplot(results,
                      ggplot2::aes(x = factor(grid_degrees),
                                   y = effective_hotspots,
                                   fill = factor(threshold))) +
  ggplot2::geom_col(position = "dodge") +
  ggplot2::labs(title = "Effective hotspots by grid resolution",
                x = "Grid degrees",
                y = "Effective hotspots",
                fill = "Hotspot percentile") +
  ggplot2::theme_minimal()

ggplot2::ggsave("outputs/figures/sensitivity_grid_resolution.png",
                p2, width = 8, height = 5, dpi = 300)
```

---

## 3. Step 11: Visualization & Report (`R/11_visualization.R`)

### Viva / Defense Explanation
> *"Step 11 generates all deliverables: 10 maps and 3 sampling-effort scatter plots. High recorded biodiversity can simply be an artifact of sampling bias (more research vessels visiting certain waters). By plotting effort against richness and against the final hotspot score, we explicitly test and document sampling bias. Finally, the script compiles `analysis_summary.csv` and auto-generates `results_report.md`."*

### Chronological Functions Called in Step 11
1. `point_map(points, title, file, colour)`: Maps raw observation coordinates over the study area bounding polygon.
2. `save_map(grid, variable, title, file)`: Generates continuous choropleth maps using colorblind-friendly `viridis` scales.
3. `save_flag_map(grid, variable, title, file)`: Renders 3-color categorical maps (`Red = Hotspot`, `Blue = Not Hotspot`, `Grey = No Paired Observation`).
4. `ggplot2::geom_point()`: Produces the 3 effort diagnostic scatter plots.
5. `writeLines(report, ...)`: Automatically exports the structured Markdown summary report.

### Complete Code
```r
# ============================================================
# STEP 11 - MAPS, FIGURES, SUMMARY TABLES AND THE REPORT
# ============================================================
source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()

# Load the processed analysis and cleaned points
grid_analysis   <- readRDS("data/processed/grid_analysis.rds")
mp              <- readRDS("data/interim/microplastics_clean.rds")
bio             <- readRDS("data/interim/biodiversity_clean.rds")

# ================================================================
# A. THE MAPS
# ================================================================

# Helper function for observation point maps
point_map <- function(points, title, file, colour) {
  p <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = study_area(cfg),
                     fill  = "#eaf3f8",
                     colour = "grey70") +
    ggplot2::geom_sf(data = points,
                     colour = colour,
                     alpha   = 0.65,
                     size    = 0.8) +
    ggplot2::labs(title = title, x = "Longitude", y = "Latitude") +
    ggplot2::coord_sf(expand = FALSE) +
    ggplot2::theme_minimal(base_size = 12)

  ggplot2::ggsave(file, p, width = 12, height = 7, dpi = 300)
}

# A1. Observation location maps
point_map(mp,  "Microplastic observation locations",
          "outputs/maps/microplastic_observation_locations.png", "#d7301f")
point_map(bio, "Biodiversity observation locations",
          "outputs/maps/biodiversity_observation_locations.png", "#225ea8")

# A2. Continuous-variable maps (save_map from utils.R)
save_map(grid_analysis, "mean_microplastic",
         "Mean microplastic concentration by grid cell",
         "outputs/maps/mean_microplastic.png")
save_map(grid_analysis, "species_richness",
         "Observed species richness by grid cell",
         "outputs/maps/species_richness.png")
save_map(grid_analysis, "hotspot_score",
         "Pollution-biodiversity hotspot score",
         "outputs/maps/hotspot_score.png")

# A3. Categorical Hotspot maps (save_flag_map from utils.R)
save_flag_map(grid_analysis, "pollution_hotspot",
              "Pollution hotspots",
              "outputs/maps/pollution_hotspots.png")
save_flag_map(grid_analysis, "biodiversity_hotspot",
              "Biodiversity hotspots",
              "outputs/maps/biodiversity_hotspots.png")
save_flag_map(grid_analysis, "effective_hotspot",
              "Effective hotspots",
              "outputs/maps/effective_hotspots.png")

# A4. DBSCAN cluster map
cluster_table <- readr::read_csv("outputs/tables/dbscan_results.csv", show_col_types = FALSE)
cluster_grid <- if ("cell_id" %in% names(cluster_table)) {
  grid_analysis |> dplyr::left_join(cluster_table, by = "cell_id")
} else {
  grid_analysis |> dplyr::mutate(dbscan_cluster = NA_integer_)
}

p_cluster <- ggplot2::ggplot(cluster_grid) +
  ggplot2::geom_sf(ggplot2::aes(fill = factor(dbscan_cluster)), colour = NA) +
  ggplot2::scale_fill_discrete(na.value = "grey90") +
  ggplot2::labs(title = "DBSCAN clusters of high-priority cells",
                fill = "Cluster", x = "Longitude", y = "Latitude") +
  ggplot2::coord_sf(expand = FALSE) +
  ggplot2::theme_minimal(base_size = 12)

ggplot2::ggsave("outputs/maps/dbscan_clusters.png", p_cluster, width = 12, height = 7, dpi = 300)

# ================================================================
# B. SAMPLING EFFORT CHECK FIGURES
# ================================================================
paired_cells <- sf::st_drop_geometry(grid_analysis) |>
  dplyr::filter(!is.na(hotspot_score))

if (nrow(paired_cells) > 1) {
  # 1. Effort vs Species Richness
  p_eff_bio <- ggplot2::ggplot(paired_cells,
                               ggplot2::aes(x = biodiversity_occurrence_count, y = species_richness)) +
    ggplot2::geom_point(alpha = 0.7) +
    ggplot2::labs(title = "Species richness and sampling effort",
                  x = "Biodiversity occurrence count", y = "Species richness") +
    ggplot2::theme_minimal()
  ggplot2::ggsave("outputs/figures/richness_vs_sampling_effort.png", p_eff_bio, width = 7, height = 5, dpi = 300)

  # 2. Effort vs Pollution/Stressor
  p_eff_mp <- ggplot2::ggplot(paired_cells,
                              ggplot2::aes(x = microplastic_sample_count, y = mean_microplastic)) +
    ggplot2::geom_point(alpha = 0.7) +
    ggplot2::labs(title = "Microplastic concentration and sampling effort",
                  x = "Microplastic sample count", y = "Mean microplastic concentration") +
    ggplot2::theme_minimal()
  ggplot2::ggsave("outputs/figures/pollution_vs_sampling_effort.png", p_eff_mp, width = 7, height = 5, dpi = 300)

  # 3. Combined Effort vs Final Hotspot Score
  p_eff_comb <- ggplot2::ggplot(paired_cells,
                                ggplot2::aes(x = microplastic_sample_count + biodiversity_occurrence_count,
                                             y = hotspot_score)) +
    ggplot2::geom_point(alpha = 0.7) +
    ggplot2::labs(title = "Hotspot score and combined sampling density",
                  x = "Microplastic samples + biodiversity occurrences", y = "Hotspot score") +
    ggplot2::theme_minimal()
  ggplot2::ggsave("outputs/figures/hotspot_score_vs_sampling_density.png", p_eff_comb, width = 7, height = 5, dpi = 300)
}

# ================================================================
# C. SUMMARY TABLE AND REPORT GENERATION
# ================================================================
analysis_summary <- sf::st_drop_geometry(grid_analysis) |>
  dplyr::summarise(
    grid_cells           = dplyr::n(),
    valid_paired_cells   = sum(!is.na(hotspot_score)),
    pollution_hotspots   = sum(pollution_hotspot,   na.rm = TRUE),
    biodiversity_hotspots = sum(biodiversity_hotspot, na.rm = TRUE),
    effective_hotspots   = sum(effective_hotspot,   na.rm = TRUE)
  )
readr::write_csv(analysis_summary, "outputs/tables/analysis_summary.csv")

# Generate Results Report markdown
report <- c(
  "# Results report", "",
  "## Scope",
  paste("This report identifies observed overlap between reported microplastic",
        "concentration and observed species richness in a common Indian Ocean",
        "grid. It does not infer causality."), "",
  "## Dataset and grid summary",
  paste0("Grid cells: ", analysis_summary$grid_cells),
  paste0("Cells with both observation layers: ", analysis_summary$valid_paired_cells), "",
  "## Hotspot results",
  paste0("Pollution hotspots: ", analysis_summary$pollution_hotspots),
  paste0("Biodiversity hotspots: ", analysis_summary$biodiversity_hotspots),
  paste0("Effective hotspots: ", analysis_summary$effective_hotspots), "",
  "## Limitations",
  paste("Uneven sampling, temporal mismatch, heterogeneous microplastic methods,",
        "the chosen grid resolution, and occurrence-record bias can affect these",
        "observed patterns. Missing records remain missing; they are never treated as zero.")
)
writeLines(report, "outputs/results/results_report.md")
```

---

## 4. Key Methodological Takeaways (Summary for Examiners)

1. **Modular Architecture:** All shared logic is isolated in `R/utils.R`. Step scripts act as clean controllers, avoiding duplicate code.
2. **Missing $\neq$ Zero:** An unmeasured ocean cell is kept as `NA`, never zero. Zero implies clean water, whereas `NA` reflects lack of sampling.
3. **Multiplicative Rank Product ($P \times B$):** Normalizes concentration and richness to $0\dots1$ via `percent_rank()`. Multiplication ensures a high score is achieved **only** when both stressor exposure and species richness are simultaneously high.
4. **Spatial Autocorrelation ($G_i^*$, Moran's I):** Replaces subjective thresholding with rigorous statistical significance and multiple testing corrections (Benjamini-Hochberg).
