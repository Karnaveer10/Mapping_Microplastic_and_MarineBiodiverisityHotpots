# Run from project root: Rscript scripts/run_pipeline.R
steps <- sprintf("R/%02d_%s.R", 1:11, c("download_data", "clean_microplastics", "clean_biodiversity", "create_grid", "spatial_join", "pollution_analysis", "biodiversity_analysis", "hotspot_analysis", "spatial_statistics", "sensitivity_analysis", "visualization"))
source("config.R"); source("R/utils.R"); ensure_dirs(); source(steps[[1]])
if (!file.exists(cfg$paths$microplastics_raw) || !file.exists(cfg$paths$biodiversity_raw)) stop("Official raw CSV inputs are missing. See data/raw/source_metadata.csv and README.md. No analysis outputs were created.", call. = FALSE)
for (i in seq_along(steps[-1])) { message(sprintf("[%d/10] %s", i, basename(steps[-1][[i]]))); source(steps[-1][[i]]) }
message("Pipeline completed with official input files.")
