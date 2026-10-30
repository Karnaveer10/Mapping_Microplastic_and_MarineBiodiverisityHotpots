source("config.R"); source("R/utils.R"); load_project_packages(); ensure_dirs(); saveRDS(make_grid(cfg), "data/interim/grid_0.5deg.rds")
