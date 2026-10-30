source("config.R"); source("R/utils.R"); load_project_packages(); ensure_dirs()
mp <- readRDS("data/interim/microplastics_clean.rds") |> sf::st_drop_geometry()
summary <- mp |> dplyr::summarise(observation_count = dplyr::n(), mean = mean(concentration), median = stats::median(concentration), sd = stats::sd(concentration), min = min(concentration), q25 = stats::quantile(concentration, .25), q50 = stats::quantile(concentration, .50), q75 = stats::quantile(concentration, .75), q80 = stats::quantile(concentration, .80), q90 = stats::quantile(concentration, .90), q95 = stats::quantile(concentration, .95), max = max(concentration))
readr::write_csv(summary, "outputs/tables/microplastic_eda_summary.csv")
audits <- dplyr::bind_rows(readr::read_csv("outputs/tables/microplastic_cleaning_summary.csv", show_col_types = FALSE), readr::read_csv("outputs/tables/biodiversity_cleaning_summary.csv", show_col_types = FALSE))
readr::write_csv(audits, "outputs/tables/data_cleaning_summary.csv")
p <- ggplot2::ggplot(mp, ggplot2::aes(concentration)) + ggplot2::geom_histogram(bins = 30, fill = "#2c7fb8", colour = "white") + ggplot2::labs(title = "Microplastic concentration distribution", x = "Reported concentration", y = "Observations") + ggplot2::theme_minimal()
ggplot2::ggsave("outputs/figures/microplastic_distribution.png", p, width = 8, height = 5, dpi = 300)
if (all(mp$concentration >= 0)) { p <- ggplot2::ggplot(mp, ggplot2::aes(log1p(concentration))) + ggplot2::geom_histogram(bins = 30, fill = "#41ab5d", colour = "white") + ggplot2::labs(title = "Log-transformed microplastic concentration", x = "log(1 + reported concentration)", y = "Observations") + ggplot2::theme_minimal(); ggplot2::ggsave("outputs/figures/microplastic_log_distribution.png", p, width = 8, height = 5, dpi = 300) }
