source("config.R"); source("R/utils.R"); load_project_packages(); ensure_dirs()
stopifnot(file.exists(cfg$paths$biodiversity_raw)); bio <- read_biodiversity(cfg$paths$biodiversity_raw, cfg)
saveRDS(bio$data, "data/interim/biodiversity_clean.rds"); readr::write_csv(bio$audit, "outputs/tables/biodiversity_cleaning_summary.csv")
