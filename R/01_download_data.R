# ============================================================
# STEP 1 - RECORD WHERE THE DATA CAME FROM
# ============================================================
# WHAT THIS STEP DOES
#   It does NOT download anything.
#   It writes two small documentation files:
#     1. data/raw/source_metadata.csv  - who provided the data and when
#     2. data/DATA_DICTIONARY.csv      - which column means what
#
# WHY?
#   In any real research project the DATA PROVENANCE matters as much as
#   the result. A reader must be able to answer: where did this come from,
#   what filters were applied, and what does each column represent?
#   Writing these files automatically means we can never forget to document.
#
# STEP ORDER NOTE
#   This file runs first so the documentation exists even if the pipeline
#   later stops for a missing input.
# ============================================================


# ---- Load the settings and the helper functions we need --------------------
source("config.R")        # brings in the `cfg` list
source("R/utils.R")       # brings in our own helper functions

ensure_dirs()             # make sure all output folders exist

load_project_packages()   # attach sf, dplyr, readr, tibble, etc.


# ---- STEP 1a: the provenance table ------------------------------------------
# tibble() builds a small, clean table.
#
# c() is used for the columns that need several values.
# as.character(Sys.Date()) turns today's date into text so it can be
# written into the CSV.
#
# The text is assembled with paste(...) so the sentence stays readable
# in the spreadsheet instead of being one run-on line.
template <- tibble::tibble(
  dataset = c("NOAA NCEI Marine Microplastics",
              "OBIS / IndOBIS marine occurrences"),

  provider = c("NOAA National Centers for Environmental Information",
               "Ocean Biodiversity Information System"),

  url = c(cfg$sources$microplastics,
          cfg$sources$biodiversity),

  required_filename = c(basename(cfg$paths$microplastics_raw),
                        basename(cfg$paths$biodiversity_raw)),

  access_date = as.character(Sys.Date()),

  required_fields = c(
    paste("longitude, latitude, concentration;",
          "retain date, depth, sample type and method where supplied"),
    paste("decimalLongitude, decimalLatitude, scientificName;",
          "retain occurrenceID, eventID and taxonomic fields where supplied")
  ),

  status = "Place an official CSV export in data/raw"
)

# Save it as CSV so it can be opened in Excel.
readr::write_csv(template, cfg$paths$metadata)


# ---- STEP 1b: the data dictionary -------------------------------------------
# tribble() is a tibble() helper where each input row becomes one output
# row - much easier to read than a long c() vector.
#
# It answers the question a reviewer always asks:
# "which column of my file did you actually use, and what did you do with it?"
dictionary <- tibble::tribble(
  ~dataset,     ~analysis_variable,     ~accepted_input_columns,                     ~use,
  "microplastics", "longitude",        "longitude | lon | decimalLongitude",        "spatial location",
  "microplastics", "latitude",         "latitude | lat | decimalLatitude",          "spatial location",
  "microplastics", "concentration",    "concentration | microplastic_concentration | particles_per_liter | pieces_per_litre | value", "primary pollution measure",
  "biodiversity",  "longitude",        "decimalLongitude | longitude | lon",        "spatial location",
  "biodiversity",  "latitude",         "decimalLatitude | latitude | lat",          "spatial location",
  "biodiversity",  "scientific_name",  "scientificName | scientific_name | species","species-richness calculation",
  "biodiversity",  "taxonomic_group",  "phylum | class | taxonomic_group",          "optional taxonomic-group richness"
)

readr::write_csv(dictionary, "data/DATA_DICTIONARY.csv")


message("Data provenance and data dictionary written.")
message("Official raw CSVs are required before analysis can run.")