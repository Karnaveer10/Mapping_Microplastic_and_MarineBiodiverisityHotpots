source("config.R"); source("R/utils.R"); load_project_packages(); ensure_dirs()
mp <- readRDS("data/interim/microplastics_clean.rds"); bio <- readRDS("data/interim/biodiversity_clean.rds")
out <- tidyr::crossing(grid_degrees = cfg$sensitivity_resolutions, threshold = cfg$sensitivity_thresholds) |> dplyr::mutate(result = purrr::map2(grid_degrees, threshold, function(resolution, threshold) {
  grid <- make_grid(cfg, resolution); mpj <- assign_cells(mp, grid)$data; bioj <- assign_cells(bio, grid)$data
  x <- score_hotspots(aggregate_grid(mpj, bioj, grid), threshold)
  tibble::tibble(valid_paired_cells = sum(!is.na(x$hotspot_score)), pollution_hotspots = sum(x$pollution_hotspot, na.rm = TRUE), biodiversity_hotspots = sum(x$biodiversity_hotspot, na.rm = TRUE), effective_hotspots = sum(x$effective_hotspot, na.rm = TRUE))
})) |> tidyr::unnest(result)
readr::write_csv(out, "outputs/tables/sensitivity_analysis.csv")
p <- ggplot2::ggplot(out, ggplot2::aes(factor(threshold), effective_hotspots, fill = factor(grid_degrees))) + ggplot2::geom_col(position = "dodge") + ggplot2::labs(title = "Effective hotspots by threshold and grid resolution", x = "Hotspot percentile", y = "Effective hotspots", fill = "Grid degrees") + ggplot2::theme_minimal()
ggplot2::ggsave("outputs/figures/sensitivity_thresholds.png", p, width = 8, height = 5, dpi = 300)
p <- ggplot2::ggplot(out, ggplot2::aes(factor(grid_degrees), effective_hotspots, fill = factor(threshold))) + ggplot2::geom_col(position = "dodge") + ggplot2::labs(title = "Effective hotspots by grid resolution", x = "Grid degrees", y = "Effective hotspots", fill = "Hotspot percentile") + ggplot2::theme_minimal()
ggplot2::ggsave("outputs/figures/sensitivity_grid_resolution.png", p, width = 8, height = 5, dpi = 300)
