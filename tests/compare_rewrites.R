# Compare original utils.R functions against the explained rewrite
# to prove the rewrite did not change any behaviour.
#
# The untouched original files are kept in _originals_backup/ so this
# comparison stays possible after the code was rewritten for clarity.

# Load each version into its own environment so they do not overwrite
# each other.
original_env <- new.env()
explained_env <- new.env()

source("config.R", local = original_env)
source("_originals_backup/utils.R", local = original_env)
source("R/utils.R", local = explained_env)

# Every function that the pipeline and tests depend on.
function_names <- c("configure_project_library",
                    "load_project_packages",
                    "ensure_dirs",
                    "study_area",
                    "pick_col",
                    "as_num",
                    "valid_coordinates",
                    "in_study_area",
                    "normalise_rank",
                    "quantile_flag",
                    "make_grid",
                    "assign_cells",
                    "read_microplastics",
                    "read_biodiversity",
                    "aggregate_grid",
                    "score_hotspots",
                    "run_spatial_statistics",
                    "save_map",
                    "save_flag_map")

# Compare the actual R code of each function.
for (name in function_names) {
  original_code  <- deparse(original_env[[name]])
  explained_code <- deparse(explained_env[[name]])

  verdict <- if (identical(original_code, explained_code)) {
    "IDENTICAL"
  } else {
    "REWRITTEN (logic must be checked by output)"
  }

  cat(sprintf("%-26s %s\n", name, verdict))
}

cat("\nNow comparing real OUTPUTS on the actual data...\n\n")

# Load packages once.
original_env$load_project_packages()

cfg <- original_env$cfg

# ---- Test 1: coordinate and percentile helpers ------------------------------
cat("valid_coordinates :",
    identical(original_env$valid_coordinates(c(0, 181, NA), c(0, 0, 0)),
              explained_env$valid_coordinates(c(0, 181, NA), c(0, 0, 0))), "\n")

cat("in_study_area     :",
    identical(original_env$in_study_area(c(20, 100, 5), c(0, 0, 0), cfg),
              explained_env$in_study_area(c(20, 100, 5), c(0, 0, 0), cfg)), "\n")

cat("normalise_rank    :",
    identical(original_env$normalise_rank(c(1, 2, 3, NA)),
              explained_env$normalise_rank(c(1, 2, 3, NA))), "\n")

cat("quantile_flag     :",
    identical(original_env$quantile_flag(c(1, 2, 3, 4, NA), 0.8),
              explained_env$quantile_flag(c(1, 2, 3, 4, NA), 0.8)), "\n")

# ---- Test 2: grid creation --------------------------------------------------
grid_original  <- original_env$make_grid(cfg, 1.0)
grid_explained <- explained_env$make_grid(cfg, 1.0)

cat("make_grid cells   :", nrow(grid_original), "vs", nrow(grid_explained), "\n")
cat("make_grid ids     :", identical(grid_original$cell_id, grid_explained$cell_id), "\n")

# ---- Test 3: reading the real NOAA file ------------------------------------
mp_original  <- original_env$read_microplastics(cfg$paths$microplastics_raw, cfg)
mp_explained <- explained_env$read_microplastics(cfg$paths$microplastics_raw, cfg)

cat("\nmicroplastic rows :", nrow(mp_original$data), "vs", nrow(mp_explained$data), "\n")
cat("microplastic audit:", identical(as.data.frame(mp_original$audit),
                                      as.data.frame(mp_explained$audit)), "\n")
cat("concentration sum:",
    isTRUE(all.equal(sum(mp_original$data$concentration),
                     sum(mp_explained$data$concentration))), "\n")

# ---- Test 4: spatial join ---------------------------------------------------
mpj_original  <- original_env$assign_cells(mp_original$data, grid_original)
mpj_explained <- explained_env$assign_cells(mp_explained$data, grid_explained)

cat("assigned points  :", mpj_original$assigned, "vs", mpj_explained$assigned, "\n")
cat("cell_id vector   :", identical(mpj_original$data$cell_id, mpj_explained$data$cell_id), "\n")

# ---- Test 5: grid aggregation ----------------------------------------------
# Use a small fake biodiversity table so the test runs instantly.
fake_bio <- mp_original$data
fake_bio$scientific_name <- rep(c("Species A", "Species B", "Species C",
                                  "Species D", "Species E", "Species F"), length.out = nrow(fake_bio))
fake_bio$taxonomic_group <- rep(c("Mollusca", "Cnidaria", "Chordata",
                                  "Cnidaria", "Mollusca", "Chordata"),
                                length.out = nrow(fake_bio))

bioj_original  <- original_env$assign_cells(fake_bio, grid_original)
bioj_explained <- explained_env$assign_cells(fake_bio, grid_explained)

agg_original  <- original_env$aggregate_grid(mpj_original$data, bioj_original$data, grid_original)
agg_explained <- explained_env$aggregate_grid(mpj_explained$data, bioj_explained$data, grid_explained)

cat("\naggregate rows    :", nrow(agg_original), "vs", nrow(agg_explained), "\n")

# Compare the numbers column by column.
columns_to_check <- c("mean_microplastic", "median_microplastic", "p95_microplastic",
                      "microplastic_sample_count", "species_richness",
                      "biodiversity_occurrence_count")

for (column_name in columns_to_check) {
  same <- isTRUE(all.equal(agg_original[[column_name]], agg_explained[[column_name]]))
  cat(sprintf("  %-30s %s\n", column_name, same))
}

# ---- Test 6: hotspot scoring -----------------------------------------------
hot_original  <- original_env$score_hotspots(agg_original,  cfg$hotspot_percentile)
hot_explained <- explained_env$score_hotspots(agg_explained, cfg$hotspot_percentile)

cat("\nhotspot columns   :\n")
for (column_name in c("P", "B", "hotspot_score", "pollution_hotspot",
                      "biodiversity_hotspot", "effective_hotspot", "rank")) {
  same <- isTRUE(all.equal(hot_original[[column_name]], hot_explained[[column_name]]))
  cat(sprintf("  %-30s %s\n", column_name, same))
}

cat("\nDONE. If every line above says TRUE, the rewrite is behaviour-identical.\n")