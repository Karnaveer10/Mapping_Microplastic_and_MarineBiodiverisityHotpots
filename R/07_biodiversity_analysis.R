# ============================================================
# STEP 7 - EXPLORE AND SUMMARISE THE BIODIVERSITY DATA (EDA)
# ============================================================
# WHAT THIS STEP DOES
#   The biodiversity equivalent of step 6. It answers two questions:
#
#   1. How many occurrence records do we have, and how many DIFFERENT
#      species do they represent?
#   2. Which species were recorded most often?
#
#   Outputs:
#     outputs/tables/biodiversity_eda_summary.csv
#     outputs/figures/biodiversity_top_species.png   (horizontal bar chart)
#
# WHY THE DIFFERENCE BETWEEN RECORDS AND SPECIES MATTERS
#   These two numbers are very different and both are needed:
#     occurrence_count    = total number of sighting records
#     unique_species_count = number of different species names
#   10,000 records of 40 species means intense sampling of a low-diversity
#   area, while 200 records of 180 species means genuinely diverse water.
#   Species richness (step 8) uses the second number, but the first tells
#   us how much we should trust it.
#
# WHY A HORIZONTAL BAR CHART
#   Scientific names are long text labels. On a vertical chart they would
#   overlap and become unreadable, so coord_flip() turns the chart sideways
#   so the names read left to right.
# ============================================================


# ---- Set-up -----------------------------------------------------------------
source("config.R")
source("R/utils.R")
ensure_dirs()
load_project_packages()


# ---- Load the cleaned biodiversity points ------------------------------------
# st_drop_geometry() removes the map shapes; we only need the columns.
bio <- readRDS("data/interim/biodiversity_clean.rds") |>
  sf::st_drop_geometry()


# ---- 1. Overall summary ------------------------------------------------------
summary_table <- bio |>
  dplyr::summarise(
    occurrence_count     = dplyr::n(),                     # total records
    unique_species_count = dplyr::n_distinct(scientific_name)  # different species
  )

readr::write_csv(summary_table, "outputs/tables/biodiversity_eda_summary.csv")


# ---- 2. Count records per species and keep the top 20 ------------------------
# count() groups by species and counts rows in each group.
# sort = TRUE puts the largest counts first.
# slice_head(n = 20) keeps only the first 20 rows.
counts <- bio |>
  dplyr::count(scientific_name, sort = TRUE) |>
  dplyr::slice_head(n = 20)


# ---- 3. Draw the horizontal bar chart ----------------------------------------
# reorder() inside aes() sorts the bars by count, so the biggest is on top.
# coord_flip() flips x and y so the bars lie horizontally.
p <- ggplot2::ggplot(counts,
                     ggplot2::aes(x = stats::reorder(scientific_name, n),
                                  y = n)) +
  ggplot2::geom_col(fill = "#756bb1") +
  ggplot2::coord_flip() +
  ggplot2::labs(title = "Most frequently observed species",
                x = "Scientific name",
                y = "Occurrences") +
  ggplot2::theme_minimal()

ggplot2::ggsave("outputs/figures/biodiversity_top_species.png",
                p, width = 9, height = 7, dpi = 300)