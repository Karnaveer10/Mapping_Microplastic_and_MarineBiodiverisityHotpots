# ==============================================================================
# SENSITIVITY SPATIAL OVERLAP & JACCARD SIMILARITY CALCULATION (OPTIMIZED)
# ==============================================================================

source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()

cat("1. Loading pre-cleaned datasets...\n")
mp  <- readRDS("data/interim/microplastics_clean.rds")
bio <- readRDS("data/interim/biodiversity_clean.rds")

mp_coords  <- sf::st_coordinates(mp)
bio_coords <- sf::st_coordinates(bio)

fast_cell_id <- function(coords, res, cfg) {
  xmin <- cfg$study_bbox[["xmin"]]
  ymin <- cfg$study_bbox[["ymin"]]
  west <- floor((coords[, 1] - xmin) / res) * res + xmin
  south <- floor((coords[, 2] - ymin) / res) * res + ymin
  sprintf("IO_%0.1f_%0.1f", west, south)
}

# Resolutions and thresholds
resolutions <- c(0.5, 1.0)
thresholds  <- c(0.70, 0.80, 0.90)

cat("2. Scoring all 6 sensitivity scenarios...\n")
scenarios <- list()

for (res in resolutions) {
  # Build grid
  grid <- make_grid(cfg, resolution = res)
  
  # Fast cell assignment
  mp_df <- sf::st_drop_geometry(mp)
  mp_df$cell_id <- fast_cell_id(mp_coords, res, cfg)
  
  bio_df <- sf::st_drop_geometry(bio)
  bio_df$cell_id <- fast_cell_id(bio_coords, res, cfg)
  
  # Aggregate
  grid_agg <- aggregate_grid(mp_df, bio_df, grid)
  
  for (th in thresholds) {
    name <- sprintf("res_%0.1f_th_%0.2f", res, th)
    scored <- score_hotspots(grid_agg, threshold = th, domain = cfg$hotspot_domain)
    
    # Filter effective hotspots
    hs_cells <- scored$cell_id[which(scored$effective_hotspot == TRUE)]
    
    # Parent 1.0 deg mapping for 0.5 deg cells
    if (res == 0.5) {
      # Extract lon, lat from cell_id "IO_lon_lat"
      parts <- strsplit(hs_cells, "_")
      lons <- as.numeric(sapply(parts, `[`, 2))
      lats <- as.numeric(sapply(parts, `[`, 3))
      p_west  <- floor((lons - cfg$study_bbox[["xmin"]]) / 1.0) * 1.0 + cfg$study_bbox[["xmin"]]
      p_south <- floor((lats - cfg$study_bbox[["ymin"]]) / 1.0) * 1.0 + cfg$study_bbox[["ymin"]]
      parent_1deg <- sprintf("IO_%0.1f_%0.1f", p_west, p_south)
    } else {
      parent_1deg <- hs_cells
    }
    
    scenarios[[name]] <- list(
      name = name,
      resolution = res,
      threshold = th,
      n_hotspots = length(hs_cells),
      cell_ids = hs_cells,
      parent_1deg = parent_1deg
    )
    cat(sprintf("  [%s]: %d effective hotspot cells\n", name, length(hs_cells)))
  }
}

cat("\n3. Computing Pairwise Jaccard Overlap Matrix...\n")
scenario_names <- names(scenarios)
rows <- list()

for (i in seq_along(scenario_names)) {
  for (j in seq_along(scenario_names)) {
    a <- scenarios[[scenario_names[i]]]
    b <- scenarios[[scenario_names[j]]]
    
    # Within same resolution
    if (a$resolution == b$resolution) {
      inter_cells <- length(intersect(a$cell_ids, b$cell_ids))
      union_cells <- length(union(a$cell_ids, b$cell_ids))
      jaccard_direct <- round((inter_cells / max(1, union_cells)) * 100, 2)
      overlap_a_pct  <- round((inter_cells / max(1, a$n_hotspots)) * 100, 2)
    } else {
      inter_cells    <- NA_integer_
      jaccard_direct <- NA_real_
      overlap_a_pct  <- NA_real_
    }
    
    # Parent 1.0 deg comparison (Aggregated resolution comparison)
    p_inter <- length(intersect(unique(a$parent_1deg), unique(b$parent_1deg)))
    p_union <- length(union(unique(a$parent_1deg), unique(b$parent_1deg)))
    jaccard_parent <- round((p_inter / max(1, p_union)) * 100, 2)
    
    # Area Overlap Calculation
    # Each 0.5 deg cell = 0.25 sq deg (~3,080 km^2 at equator)
    # Each 1.0 deg cell = 1.00 sq deg (~12,320 km^2 at equator)
    # Cross-resolution area overlap:
    if (a$resolution == b$resolution) {
      jaccard_area <- jaccard_direct
    } else {
      # For cross-resolution (e.g. 0.5 deg vs 1.0 deg):
      # A 0.5 deg cell is inside a 1.0 deg cell if its parent_1deg is in b's cell_ids
      if (a$resolution == 0.5) {
        matched_05_cells <- sum(a$parent_1deg %in% b$cell_ids)
        area_inter_sqdeg <- matched_05_cells * 0.25
        area_a_sqdeg     <- a$n_hotspots * 0.25
        area_b_sqdeg     <- b$n_hotspots * 1.00
      } else {
        matched_05_cells <- sum(b$parent_1deg %in% a$cell_ids)
        area_inter_sqdeg <- matched_05_cells * 0.25
        area_a_sqdeg     <- a$n_hotspots * 1.00
        area_b_sqdeg     <- b$n_hotspots * 0.25
      }
      area_union_sqdeg <- area_a_sqdeg + area_b_sqdeg - area_inter_sqdeg
      jaccard_area     <- round((area_inter_sqdeg / max(0.01, area_union_sqdeg)) * 100, 2)
    }
    
    rows[[length(rows) + 1]] <- data.frame(
      Scenario_A = a$name,
      Resolution_A = a$resolution,
      Threshold_A = a$threshold,
      Hotspots_A = a$n_hotspots,
      Scenario_B = b$name,
      Resolution_B = b$resolution,
      Threshold_B = b$threshold,
      Hotspots_B = b$n_hotspots,
      Shared_Cells = inter_cells,
      Jaccard_Cell_Pct = jaccard_direct,
      Retention_Pct = overlap_a_pct,
      Parent_1deg_Jaccard_Pct = jaccard_parent,
      Area_Jaccard_Pct = jaccard_area,
      stringsAsFactors = FALSE
    )
  }
}

overlap_df <- do.call(rbind, rows)
readr::write_csv(overlap_df, "outputs/tables/sensitivity_spatial_overlap.csv")
cat("Saved outputs/tables/sensitivity_spatial_overlap.csv\n\n")

# Display Baseline comparison table
cat("========================================================================================\n")
cat("SPATIAL OVERLAP RELATIVE TO BASELINE (0.5 deg Grid, 80th Percentile Threshold)\n")
cat("========================================================================================\n")
base_view <- subset(overlap_df, Scenario_A == "res_0.5_th_0.80")
print(base_view[, c("Scenario_B", "Hotspots_B", "Shared_Cells", "Jaccard_Cell_Pct", "Retention_Pct", "Area_Jaccard_Pct")])
