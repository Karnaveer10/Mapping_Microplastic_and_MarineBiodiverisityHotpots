# ============================================================
# STEP 10 - SENSITIVITY ANALYSIS
# ============================================================
# WHAT THIS STEP DOES
#   Repeats the entire hotspot analysis under different settings to check
#   that our main answer is not just an artefact of two arbitrary choices:
#
#       1. the hotspot threshold (70th / 80th / 90th percentile)
#       2. the grid resolution  (0.5 / 1.0 degrees)
#
#   2 resolutions x 3 thresholds = 6 separate runs of the whole pipeline.
#
# WHY THIS MATTERS
#   A reviewer can always ask: "what if you had picked a different
#   threshold?" This step means we can answer with evidence instead of an
#   opinion. If the same regions stay in the top ranks across all six
#   runs, the conclusion is robust.
#
# OUTPUTS
#   outputs/tables/sensitivity_analysis.csv
#   outputs/figures/sensitivity_thresholds.png
#   outputs/figures/sensitivity_grid_resolution.png
#
# THE KEY FUNCTION HERE IS purrr::map2()
#   It applies a function to every PAIR of values taken from two vectors
#   at the same time. Instead of writing six nearly identical blocks of
#   code, we write the analysis once and let map2() run it six times.
#   This is called functional programming and it removes repetition.
# ============================================================


# ---- Set-up -----------------------------------------------------------------
source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()


# ---- Load the cleaned points once (they do not change) -----------------------
mp  <- readRDS("data/interim/microplastics_clean.rds")
bio <- readRDS("data/interim/biodiversity_clean.rds")


# ---- Run all six combinations -------------------------------------------------
# crossing() builds the table of every possible pair:
#     grid_degrees : 0.5, 0.5, 0.5, 1.0, 1.0, 1.0
#     threshold    : 0.70, 0.80, 0.90, 0.70, 0.80, 0.90
#
# map2() then runs our analysis function once per row. The function
# receives two arguments: resolution and threshold.
results <- tidyr::crossing(
  grid_degrees = cfg$sensitivity_resolutions,   # c(0.5, 1.0)
  threshold    = cfg$sensitivity_thresholds    # c(0.70, 0.80, 0.90)
) |>
  dplyr::mutate(
    result = purrr::map2(grid_degrees, threshold,
                         function(resolution, threshold) {

                           # --- rebuild the grid at this resolution ---
                           grid <- make_grid(cfg, resolution)

                           # --- put both datasets into that grid ---
                           mpj  <- assign_cells(mp,  grid)$data
                           bioj <- assign_cells(bio, grid)$data

                           # --- summarise, then score with this threshold ---
                           x <- score_hotspots(
                                  aggregate_grid(mpj, bioj, grid),
                                  threshold,
                                  domain = cfg$hotspot_domain)

                           # --- return just the four headline numbers ---
                           tibble::tibble(
                             valid_paired_cells  = sum(!is.na(x$hotspot_score)),
                             pollution_hotspots   = sum(x$pollution_hotspot,   na.rm = TRUE),
                             biodiversity_hotspots = sum(x$biodiversity_hotspot, na.rm = TRUE),
                             effective_hotspots   = sum(x$effective_hotspot,   na.rm = TRUE)
                           )
                         })
  ) |>
  # map2() returned a small table inside each row. unnest() flattens those
  # six little tables so every result sits on its own single row.
  tidyr::unnest(result)

readr::write_csv(results, "outputs/tables/sensitivity_analysis.csv")


# ---- Chart 1: effect of the THRESHOLD ---------------------------------------
# position = "dodge" places the two resolutions side by side instead of
# on top of each other, so the bars can be compared directly.
# factor() turns 0.70 / 0.80 / 0.90 into categories - without it ggplot
# would treat them as numbers and draw a continuous axis.
p <- ggplot2::ggplot(results,
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
                p, width = 8, height = 5, dpi = 300)


# ---- Chart 2: effect of the GRID RESOLUTION ---------------------------------
# Same data, but with resolution on the x-axis and threshold as the colour.
# Drawing it both ways makes the interaction easy to see.
p <- ggplot2::ggplot(results,
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
                p, width = 8, height = 5, dpi = 300)