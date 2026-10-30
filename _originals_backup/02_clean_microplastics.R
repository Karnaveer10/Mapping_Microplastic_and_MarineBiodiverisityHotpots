source("config.R"); source("R/utils.R"); load_project_packages(); ensure_dirs()
stopifnot(file.exists(cfg$paths$microplastics_raw)); mp <- read_microplastics(cfg$paths$microplastics_raw, cfg)
saveRDS(mp$data, "data/interim/microplastics_clean.rds"); readr::write_csv(mp$audit, "outputs/tables/microplastic_cleaning_summary.csv")
