# ============================================================
# STEP 6 - EXPLORE AND SUMMARISE THE POLLUTION DATA (EDA)
# ============================================================
# WHAT THIS STEP DOES
#   Before combining anything, we look at the microplastic data on its own.
#   "EDA" stands for Exploratory Data Analysis.
#
#   1. Computes a statistical summary (count, mean, median, spread,
#      quartiles, maximum).
#   2. Combines both cleaning audit tables into one report table.
#   3. Draws a histogram of the raw concentrations.
#   4. Draws a second histogram after log transformation.
#
# WHY LOOK FIRST, THEN MAP?
#   Because a spatial map of a badly skewed dataset is misleading.
#   Microplastic concentration typically spans several orders of
#   magnitude, so a few extreme coastal samples can stretch the colour
#   scale and hide every normal value. Understanding the distribution
#   first tells us how to present it fairly.
#
# WHY A LOG HISTOGRAM?
#   log1p(x) means log(1 + x). It is used instead of log(x) because some
#   values may be zero, and log(0) is undefined.
#   If the log version looks roughly bell-shaped while the raw one is
#   right-skewed, that confirms the skewness - which is exactly what we
#   want to know before choosing map colours.
# ============================================================


# ---- Set-up -----------------------------------------------------------------
source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()


# ---- Load the cleaned microplastic points -----------------------------------
# st_drop_geometry() removes the map shapes. We only need the table
# columns for statistics and histograms, and dropping the geometry makes
# these operations faster.
mp <- readRDS("data/interim/microplastics_clean.rds") |>
  sf::st_drop_geometry()


# ---- 1. Statistical summary --------------------------------------------------
# summarise() reduces many rows to one row of numbers.
#   n()                  -> how many observations
#   mean()               -> average concentration
#   median()             -> middle value (not affected by outliers)
#   sd()                 -> standard deviation, i.e. how spread out
#   quantile(x, .25)     -> the 25th percentile (lower quartile)
#   min() / max()        -> smallest and largest
#
# Quartiles are included because the report needs to describe the
# distribution properly, not just quote an average.
summary_table <- mp |>
  dplyr::summarise(
    observation_count = dplyr::n(),
    mean   = mean(concentration),
    median = stats::median(concentration),
    sd     = stats::sd(concentration),
    min    = min(concentration),
    q25    = stats::quantile(concentration, .25),
    q50    = stats::quantile(concentration, .50),
    q75    = stats::quantile(concentration, .75),
    q80    = stats::quantile(concentration, .80),
    q90    = stats::quantile(concentration, .90),
    q95    = stats::quantile(concentration, .95),
    max    = max(concentration)
  )

readr::write_csv(summary_table, "outputs/tables/microplastic_eda_summary.csv")


# ---- 2. Combine both cleaning audits into one table --------------------------
# bind_rows() puts the two audit tables on top of each other so the report
# has a single "how much data did we start with, and what happened to it"
# table covering both datasets.
audits <- dplyr::bind_rows(
  readr::read_csv("outputs/tables/microplastic_cleaning_summary.csv",
                  show_col_types = FALSE),
  readr::read_csv("outputs/tables/biodiversity_cleaning_summary.csv",
                  show_col_types = FALSE)
)

readr::write_csv(audits, "outputs/tables/data_cleaning_summary.csv")


# ---- 3. Histogram of the raw concentrations ---------------------------------
# The ggplot2 grammar used throughout this project:
#   ggplot(data)        -> start with the data
#   + aes(x)             -> say which column goes on which axis
#   + geom_histogram()   -> draw this type of layer
#   + labs()             -> set the title and axis labels
#   + theme_minimal()    -> remove heavy borders for a cleaner look
p <- ggplot2::ggplot(mp, ggplot2::aes(concentration)) +
  ggplot2::geom_histogram(bins = 30, fill = "#2c7fb8", colour = "white") +
  ggplot2::labs(title = "Microplastic concentration distribution",
                x = "Reported concentration",
                y = "Observations") +
  ggplot2::theme_minimal()

ggplot2::ggsave("outputs/figures/microplastic_distribution.png",
                p, width = 8, height = 5, dpi = 300)


# ---- 4. Histogram after log transformation ----------------------------------
# GUARD: log is only valid for positive values. If any concentration is
# negative we skip this chart rather than produce a meaningless one.
# (Cleaning in step 2 already removed negatives, but this check makes the
#  script safe to run on any dataset.)
if (all(mp$concentration >= 0)) {

  p <- ggplot2::ggplot(mp, ggplot2::aes(log1p(concentration))) +
    ggplot2::geom_histogram(bins = 30, fill = "#41ab5d", colour = "white") +
    ggplot2::labs(title = "Log-transformed microplastic concentration",
                  x = "log(1 + reported concentration)",
                  y = "Observations") +
    ggplot2::theme_minimal()

  ggplot2::ggsave("outputs/figures/microplastic_log_distribution.png",
                  p, width = 8, height = 5, dpi = 300)
}