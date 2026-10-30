# ============================================================
# UTILITY FUNCTIONS  (explained, beginner-friendly version)
# ============================================================
# This file holds every reusable function used by the pipeline.
# Each function is small and does ONE job, so it is easy to
# explain line by line during the viva / presentation.
#
# Why a separate utils file?
#   - Avoids repeating the same code in 11 different scripts.
#   - One place to fix a bug instead of hunting through every file.
#   - Matches the "Functions" topic of Module 1 of our syllabus.
#
# NOTE: function NAMES are kept exactly the same as the original
#       working code, so the pipeline and the tests still run.
#       Only the *inside* of each function has been re-written
#       to be easier to read, with more comments.
# ============================================================


# ------------------------------------------------------------
# 0. PACKAGE SET-UP
# ------------------------------------------------------------

# Vector of the packages this project needs.
# A vector in R is written like c(a, b, c) - order matters, and
# every element must be the same type (here: all text).
required_packages <- c("sf",        # Handles spatial objects (points, polygons)
                      "dplyr",     # Data manipulation: filter, group_by, join
                      "readr",     # Fast and reliable CSV reading
                      "ggplot2",   # Grammar-of-graphics plotting
                      "tidyr",     # Reshaping tables (rows <-> columns)
                      "stringr",   # Clean and extract text values
                      "spdep",     # Spatial statistics (Moran's I, Getis-Ord)
                      "dbscan",    # Density based clustering
                      "scales",    # Formatting numbers/labels on graphs
                      "purrr",     # Functional programming helpers
                      "tibble")    # A cleaner printing data frame

# Where the project's own copy of the packages lives (renv folder).
project_library <- "renv/library/R-4.6"


# Use the project's local library first, then fall back to the
# normal system library. .libPaths() tells R where to search.
configure_project_library <- function() {
  if (dir.exists(project_library)) {                 # only if the folder exists
    .libPaths(c(normalizePath(project_library),       # add it as first choice
                .libPaths()))                        # then keep the usual paths
  }
  invisible(.libPaths())                             # return quietly, no printing
}

configure_project_library()   # run it immediately so paths are set for all later code


# Load (attach) every required package.
load_project_packages <- function() {
  configure_project_library()                        # make sure paths are right

  # For each required package, check if it can be found.
  # vapply() repeats the check for every package name and
  # returns one TRUE/FALSE per package (a logical vector).
  packages_found <- vapply(required_packages,
                           requireNamespace,          # the check function
                           logical(1),                # result type: TRUE/FALSE
                           quietly = TRUE)            # do not print messages

  # Packages that were NOT found
  missing <- required_packages[!packages_found]

  # If anything is missing, stop immediately with a helpful message.
  # Stopping early is better than failing later with a confusing error.
  if (length(missing) > 0) {
    stop("Install required R packages before running: ",
         paste(missing, collapse = ", "),
         call. = FALSE)
  }

  # library() actually attaches each package so we can use
  # functions like st_make_grid() instead of sf::st_make_grid().
  invisible(lapply(required_packages, library, character.only = TRUE))
}


# Create all folders the pipeline writes into.
# dir.create() is safe to call even if the folder already exists
# (that is why we silence the warnings).
ensure_dirs <- function() {
  dirs <- c("data/raw",        # untouched input files
            "data/interim",     # step-by-step working files
            "data/processed",   # final analysis-ready table
            "outputs/figures",  # statistical charts
            "outputs/maps",     # maps
            "outputs/tables",   # result tables (CSV)
            "outputs/results")  # written report

  invisible(lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE))
}


# ------------------------------------------------------------
# 1. SMALL SPATIAL AND DATA HELPER FUNCTIONS
# ------------------------------------------------------------

# Turn the four study-area numbers from config.R into a
# rectangle that sf understands as a shape.
study_area <- function(cfg) {
  sf::st_as_sfc(sf::st_bbox(cfg$study_bbox, crs = sf::st_crs(cfg$crs)))
}


# Find a column by trying several possible names.
#
# WHY?  The two data providers use different column names:
#       NOAA writes "Longitude (degree)", OBIS writes
#       "decimalLongitude". Instead of hard-coding one name we
#       accept any of a list, which makes the code robust.
#
# x        = the data frame we are searching
# choices  = the accepted column names
# required = if TRUE, stop when nothing matches
pick_col <- function(x, choices, required = TRUE) {

  # setNames() builds a lookup table: lowercase name -> real name.
  # e.g. "longitude (degree)" becomes "longitude (degree)" -> "Longitude (degree)"
  lookup <- setNames(names(x), tolower(names(x)))

  # Look up each of our accepted names in that table.
  hit <- unname(lookup[tolower(choices)])

  # Remove the ones that were not found (they come back as NA).
  hit <- hit[!is.na(hit)]

  # Nothing matched and the column is essential -> stop with a clear message.
  if (length(hit) == 0 && required) {
    stop("Required column absent. Expected one of: ",
         paste(choices, collapse = ", "),
         call. = FALSE)
  }

  # Return the first match, or NA if the column was optional and missing.
  if (length(hit) > 0) hit[[1]] else NA_character_
}


# Safely turn text into numbers.
# Some rows contain "0.01 pieces/m3" or have stray spaces / commas.
# parse_number() pulls the numeric part out; suppressWarnings hides the
# warnings produced by values that cannot be parsed (they become NA).
as_num <- function(x) {
  suppressWarnings(readr::parse_number(as.character(x)))
}


# Are the coordinates usable on the globe at all?
# Longitude must be -180..180 and latitude must be -90..90.
# NA values are rejected with !is.na(...).
valid_coordinates <- function(lon, lat) {
  !is.na(lon) & !is.na(lat) &
    lon >= -180 & lon <= 180 &
    lat >= -90  & lat <= 90
}


# Are the coordinates inside OUR study area (the Indian Ocean box)?
# This is the second filter: globally valid, but geographically irrelevant.
in_study_area <- function(lon, lat, cfg) {
  lon >= cfg$study_bbox[["xmin"]] & lon <= cfg$study_bbox[["xmax"]] &
    lat >= cfg$study_bbox[["ymin"]] & lat <= cfg$study_bbox[["ymax"]]
}


# ------------------------------------------------------------
# 2. TURNING RAW NUMBERS INTO COMPARABLE SCORES
# ------------------------------------------------------------

# Convert values to a 0-1 scale based on their RANK, not their size.
#
# WHY rank and not raw value?
#   Microplastic concentration (e.g. 0.05 to 3000 pieces/m3) and
#   species richness (e.g. 3 to 400 species) are on completely
#   different scales. Ranking puts both on 0 to 1 so they can be
#   multiplied meaningfully.
#
#   percent_rank() gives 0 to the smallest and 1 to the largest.
#   Missing values stay missing (NA) - we never turn them into 0.
normalise_rank <- function(x) {

  # Start with an answer full of NA (same length as the input).
  out <- rep(NA_real_, length(x))

  # Which values are real numbers?
  ok <- !is.na(x)

  # Edge case: only one usable value - it is both smallest and largest.
  if (sum(ok) == 1L) out[ok] <- 1

  # Normal case: two or more usable values.
  if (sum(ok) > 1L) out[ok] <- dplyr::percent_rank(x[ok])

  out
}


# Flag every value that is ABOVE a chosen percentile.
#
# threshold = 0.80 means "the top 20% of the observed cells".
# We compare against the percentile of only the cells that have data,
# so a huge empty ocean does not drag the threshold down.
quantile_flag <- function(x, threshold) {

  out <- rep(NA, length(x))        # default: we do not know
  ok  <- !is.na(x)                 # cells that have data

  # Nothing to compare - return all NA.
  if (!any(ok)) return(out)

  # The cut-off value at the requested percentile.
  # type = 7 is R's default quantile definition; we state it
  # explicitly so the result is reproducible.
  cutoff <- stats::quantile(x[ok], threshold, names = FALSE, type = 7)

  # TRUE only where the value is strictly above the cut-off.
  out[ok] <- x[ok] > cutoff

  out
}


# ------------------------------------------------------------
# 3. BUILDING THE SPATIAL GRID
# ------------------------------------------------------------

# Draw a checkerboard of square cells over the study area.
#
# resolution = 0.5 gives 0.5 degree x 0.5 degree cells (main analysis)
# resolution = 1.0 gives 1.0 degree x 1.0 degree cells (sensitivity check)
make_grid <- function(cfg, resolution = cfg$grid_degrees) {

  # Only these two resolutions have been tested, so refuse others.
  if (!resolution %in% c(0.5, 1.0)) {
    stop("Grid resolution must be 0.5 or 1.0 degrees.", call. = FALSE)
  }

  # st_make_grid() cuts the bounding rectangle into equal squares.
  grid <- sf::st_make_grid(study_area(cfg),
                           cellsize = c(resolution, resolution),
                           square = TRUE,
                           what = "polygons")

  # Put the shapes into a proper sf data frame (a table + geometry).
  grid <- sf::st_sf(geometry = grid)

  # Find the middle point of every cell.
  centers <- sf::st_coordinates(sf::st_centroid(grid))

  # Work out where the SOUTH-WEST corner of each cell is, so that
  # every cell can get a unique, human-readable name such as
  # "IO_72.5_-18.0" (west edge 72.5, south edge -18.0).
  west  <- floor((centers[, 1] - cfg$study_bbox[["xmin"]]) / resolution) * resolution + cfg$study_bbox[["xmin"]]
  south <- floor((centers[, 2] - cfg$study_bbox[["ymin"]]) / resolution) * resolution + cfg$study_bbox[["ymin"]]

  # sprintf() formats the numbers to one decimal place (%0.1f).
  grid$cell_id <- sprintf("IO_%0.1f_%0.1f", west, south)

  # Keep only the id and the shape - that is all we need from here.
  dplyr::select(grid, cell_id, geometry)
}


# ------------------------------------------------------------
# 4. JOINING POINTS TO THE GRID  (the spatial join)
# ------------------------------------------------------------

# Ask the computer: "which grid cell does each observation fall in?"
#
# st_intersects() returns, for every point, the row number(s) of the
# cell(s) it touches. vapply() then turns that list into one clean
# character value per point: the cell_id, or NA if it missed the grid.
assign_cells <- function(points, grid) {

  # For each point: which grid polygons does it overlap?
  idx <- sf::st_intersects(points, grid)

  # Convert the list-of-lists into a simple character vector.
  cell_id <- vapply(idx,
                    function(i) if (length(i) > 0) grid$cell_id[[i[[1]]]] else NA_character_,
                    character(1))

  # Attach the cell id to the original points table.
  points$cell_id <- cell_id

  # Report how many points were matched and how many were not,
  # so we can prove nothing disappeared silently.
  list(data      = points,
       assigned   = sum(!is.na(cell_id)),
       unassigned = sum(is.na(cell_id)))
}


# ------------------------------------------------------------
# 5. READING AND CLEANING THE MICROPLASTIC DATA
# ------------------------------------------------------------

# Read the NOAA microplastic CSV, clean it, and describe what was removed.
#
# RETURNS a list with two parts:
#   $data  - the cleaned points, ready for mapping
#   $audit - a one-row table counting every record we discarded and why
#
# The audit table is important for the report: it proves we did not
# silently delete data.
read_microplastics <- function(path, cfg) {

  # --- STEP 1: read the file -------------------------------------------------
  # show_col_types = FALSE  -> do not print the column summary
  # name_repair = "unique"  -> fix duplicated column names automatically
  x <- readr::read_csv(path, show_col_types = FALSE, name_repair = "unique")

  # --- STEP 2: find the three columns we need --------------------------------
  # We accept several possible names because exports change between versions.
  lon_col  <- pick_col(x, c("longitude", "lon", "decimalLongitude",
                            "longitude (degree)", "longitude(degree)"))
  lat_col  <- pick_col(x, c("latitude", "lat", "decimalLatitude",
                            "latitude (degree)", "latitude(degree)"))
  conc_col <- pick_col(x, c("concentration", "microplastic_concentration",
                            "microplastics measurement", "measurement",
                            "particles_per_liter", "pieces_per_litre", "value"))

  # --- STEP 3: create three clean numeric columns ----------------------------
  # .data[[column_name]] means "the column whose name is stored in
  # lon_col / lat_col / conc_col". This is tidyverse-style and avoids
  # the ugly x$lon_col syntax.
  x <- dplyr::mutate(x,
                     longitude    = as_num(.data[[lon_col]]),
                     latitude     = as_num(.data[[lat_col]]),
                     concentration = as_num(.data[[conc_col]]))

  # --- STEP 4: count how many records we have BEFORE cleaning ----------------
  raw <- nrow(x)

  # --- STEP 5: build one TRUE/FALSE flag per problem -------------------------
  # Each flag answers a different question about the same rows.
  bad_xy         <- !valid_coordinates(x$longitude, x$latitude)  # impossible lon/lat
  outside        <- !bad_xy & !in_study_area(x$longitude,       # valid but not in our box
                                            x$latitude, cfg)
  missing_conc   <- is.na(x$concentration)                      # no value at all
  invalid_conc   <- !missing_conc & x$concentration < 0          # negative = impossible

  # --- STEP 6: keep a row only if ALL four problems are absent ----------------
  keep <- !(bad_xy | outside | missing_conc | invalid_conc)
  candidates <- x[keep, , drop = FALSE]

  # --- STEP 7: remove exact duplicate measurements ---------------------------
  # Two records with the same lon, lat AND concentration carry no extra
  # information, so we keep only one. .keep_all = TRUE keeps the other columns.
  clean <- dplyr::distinct(candidates, longitude, latitude, concentration,
                           .keep_all = TRUE)

  # --- STEP 8: write the audit table -----------------------------------------
  audit <- tibble::tibble(
    dataset              = "microplastics",
    raw_records          = raw,
    invalid_coordinates  = sum(bad_xy),
    outside_study_area   = sum(outside),
    missing_concentration = sum(missing_conc),
    invalid_concentration = sum(invalid_conc),
    duplicates_removed   = nrow(candidates) - nrow(clean),
    remaining_records    = nrow(clean)
  )

  # If cleaning removed everything, the analysis is impossible - stop loudly.
  if (nrow(clean) == 0) {
    stop("No valid microplastic records remain inside the Indian Ocean study area.",
         call. = FALSE)
  }

  # --- STEP 9: convert lon/lat into real map points --------------------------
  # st_as_sf() builds an sf object. remove = FALSE keeps the original
  # longitude / latitude columns in the table.
  list(data = sf::st_as_sf(clean,
                           coords  = c("longitude", "latitude"),
                           crs     = cfg$crs,
                           remove  = FALSE),
       audit = audit)
}

# ------------------------------------------------------------
# 6. READING AND CLEANING THE BIODIVERSITY DATA
# ------------------------------------------------------------

# Same idea as read_microplastics(), but for OBIS species records.
# The difference: this file can be very large (over 1 GB), so we are
# careful to only add the columns we truly need.
read_biodiversity <- function(path, cfg) {

  # --- STEP 1: read the file ---------------------------------------------------
  x <- readr::read_csv(path, show_col_types = FALSE, name_repair = "unique")

  # --- STEP 2: find the columns we need ---------------------------------------
  lon_col     <- pick_col(x, c("decimalLongitude", "longitude", "lon"))
  lat_col     <- pick_col(x, c("decimalLatitude", "latitude", "lat"))
  species_col <- pick_col(x, c("scientificName", "scientific_name", "species"))

  # The taxonomic group is OPTIONAL, so required = FALSE.
  # If the file has no phylum/class column we simply create empty values
  # instead of stopping.
  group_col <- pick_col(x, c("phylum", "class", "taxonomic_group"),
                        required = FALSE)

  taxonomic_group <- if (is.na(group_col)) {
    rep(NA_character_, nrow(x))                  # no column -> all missing
  } else {
    stringr::str_squish(as.character(x[[group_col]]))  # trim extra spaces
  }

  # --- STEP 3: create clean columns -------------------------------------------
  x <- dplyr::mutate(x,
                     longitude     = as_num(.data[[lon_col]]),
                     latitude      = as_num(.data[[lat_col]]),
                     scientific_name = stringr::str_squish(as.character(.data[[species_col]])),
                     taxonomic_group = taxonomic_group)

  # --- STEP 4: remember the starting size -------------------------------------
  raw <- nrow(x)

  # --- STEP 5: the three possible problems ------------------------------------
  bad_xy     <- !valid_coordinates(x$longitude, x$latitude)
  outside    <- !bad_xy & !in_study_area(x$longitude, x$latitude, cfg)

  # A record without a species name cannot contribute to richness.
  no_species <- is.na(x$scientific_name) | x$scientific_name == ""

  # --- STEP 6: keep only good rows ---------------------------------------------
  keep <- !(bad_xy | outside | no_species)
  candidates <- x[keep, , drop = FALSE]

  # Same coordinate recorded twice for the same species adds nothing.
  clean <- dplyr::distinct(candidates, longitude, latitude, scientific_name,
                           .keep_all = TRUE)

  # --- STEP 7: audit table ------------------------------------------------------
  audit <- tibble::tibble(
    dataset                 = "biodiversity",
    raw_records             = raw,
    invalid_coordinates     = sum(bad_xy),
    outside_study_area      = sum(outside),
    missing_species_identity = sum(no_species),
    duplicates_removed      = nrow(candidates) - nrow(clean),
    remaining_records       = nrow(clean)
  )

  if (nrow(clean) == 0) {
    stop("No valid biodiversity records remain inside the Indian Ocean study area.",
         call. = FALSE)
  }

  list(data = sf::st_as_sf(clean,
                           coords  = c("longitude", "latitude"),
                           crs     = cfg$crs,
                           remove  = FALSE),
       audit = audit)
}


# ------------------------------------------------------------
# 7. SUMMARISING EVERY GRID CELL  (group_by + summarise)
# ------------------------------------------------------------

# This is the heart of the project: turn thousands of scattered
# points into ONE row per grid cell.
#
# For the microplastic points we calculate, per cell:
#   mean_microplastic         - average concentration
#   median_microplastic       - middle value (less affected by extremes)
#   p95_microplastic          - 95th percentile (shows the worst case)
#   microplastic_sample_count - how many samples support that mean
#
# For the biodiversity points:
#   species_richness              - number of DIFFERENT species names
#   taxonomic_group_richness      - number of different phyla/classes
#   biodiversity_occurrence_count - total number of records
#
# WHY keep the counts?  Because a cell with 1 sample and a cell with
# 500 samples should not be trusted equally. We report effort so
# readers can judge reliability.
aggregate_grid <- function(mp_joined, bio_joined, grid) {

  # --- STEP 1: summarise the microplastic points -----------------------------
  # st_drop_geometry() removes the map shapes because group_by() and
  # summarise() only need the table columns.
  pm <- mp_joined |>
    sf::st_drop_geometry() |>
    dplyr::filter(!is.na(cell_id)) |>           # drop points outside the grid
    dplyr::group_by(cell_id) |>                 # one group per grid cell
    dplyr::summarise(
      mean_microplastic         = mean(concentration),
      median_microplastic       = stats::median(concentration),
      p95_microplastic          = stats::quantile(concentration, .95, names = FALSE),
      microplastic_sample_count = dplyr::n(),   # n() counts rows in the group
      .groups = "drop"                          # remove the grouping afterwards
    )

  # --- STEP 2: summarise the biodiversity points ------------------------------
  bm <- bio_joined |>
    sf::st_drop_geometry() |>
    dplyr::filter(!is.na(cell_id)) |>
    dplyr::group_by(cell_id) |>
    dplyr::summarise(
      # n_distinct() counts UNIQUE values -> this is species richness
      species_richness             = dplyr::n_distinct(scientific_name),
      taxonomic_group_richness     = if (all(is.na(taxonomic_group) | taxonomic_group == "")) {
        NA_integer_                              # no group data -> missing
      } else {
        dplyr::n_distinct(taxonomic_group[!is.na(taxonomic_group) & taxonomic_group != ""])
      },
      biodiversity_occurrence_count = dplyr::n(),
      .groups = "drop"
    )

  # --- STEP 3: attach both summaries to the grid -----------------------------
  # left_join() keeps EVERY grid cell, even cells with no data.
  # That is essential: an empty cell must appear as "no observation",
  # never as a zero.
  grid |>
    dplyr::left_join(pm, by = "cell_id") |>
    dplyr::left_join(bm, by = "cell_id")
}


# ------------------------------------------------------------
# 8. TURNING THE NUMBERS INTO HOTSPOT LABELS
# ------------------------------------------------------------

# Add all hotspot columns in ONE dplyr::mutate() call.
#
# COLUMN BY COLUMN:
#
#   P = pollution score, 0-1   (rank of mean microplastic)
#   B = biodiversity score, 0-1 (rank of species richness)
#   hotspot_score = P * B
#         Why multiply?  Because a cell must be bad on BOTH sides to
#         score high. A cell with high pollution but almost no recorded
#         life scores near 0, and a low-pollution cell scores near 0 too.
#         Only "high pollution AND high diversity" scores highly.
#
#   pollution_hotspot    = TRUE if mean_microplastic is above the threshold
#   biodiversity_hotspot = TRUE if species_richness is above the threshold
#   effective_hotspot    = TRUE only when BOTH of the above are TRUE.
#                          This is the direct answer to our research question.
#   rank                 = position when sorted best to worst.
score_hotspots <- function(grid, threshold = .8) {

  # A threshold of 0 or 1 would make the comparison meaningless.
  if (threshold <= 0 || threshold >= 1) {
    stop("Hotspot threshold must be strictly between 0 and 1.", call. = FALSE)
  }

  grid |>
    dplyr::mutate(
      # ---- the two normalised 0-1 scores ----------------------------------
      P = normalise_rank(mean_microplastic),
      B = normalise_rank(species_richness),

      # ---- the combined priority score ------------------------------------
      hotspot_score = P * B,

      # ---- the threshold-based labels -------------------------------------
      pollution_hotspot    = quantile_flag(mean_microplastic, threshold),
      biodiversity_hotspot = quantile_flag(species_richness, threshold),

      # ---- the final answer: both hot at the same time ---------------------
      # if_else() needs a TRUE/FALSE in every branch, so for cells where
      # either side has no data we return NA (unknown), not FALSE.
      effective_hotspot = dplyr::if_else(
        !is.na(pollution_hotspot) & !is.na(biodiversity_hotspot),
        pollution_hotspot & biodiversity_hotspot,
        NA
      ),

      # ---- ranking: 1 = best ----------------------------------------------
      # desc() sorts from largest to smallest, min_rank() then gives 1,2,3...
      rank = dplyr::if_else(
        !is.na(hotspot_score),
        dplyr::min_rank(dplyr::desc(hotspot_score)),
        NA_integer_
      )
    )
}


# ------------------------------------------------------------
# 9. SPATIAL STATISTICS  (is the pattern clustered?)
# ------------------------------------------------------------

# Three questions are answered here:
#
#  Q1  Are high-priority cells clustered overall?        -> Moran's I
#  Q2  Which specific cells sit inside a significant
#      high-value cluster?                                -> Getis-Ord Gi*
#  Q3  Do the top cells form distinct geographic groups? -> DBSCAN
#
# IMPORTANT DESIGN CHOICE:
#   All three tests are only run when there are enough usable cells.
#   Running them on 3 cells would produce a meaningless number, so the
#   function returns an honest "not calculated" status instead of a fake result.
run_spatial_statistics <- function(grid, cfg) {

  # --- STEP 1: keep only cells that have BOTH layers of data -----------------
  # A cell with no biodiversity value has no hotspot_score, so it cannot
  # take part in the spatial tests.
  valid <- grid |> dplyr::filter(!is.na(hotspot_score))

  # Helper that returns three empty tables, each saying why nothing was run.
  insufficient <- function(reason) {
    list(moran   = tibble::tibble(status = reason),
         gi      = tibble::tibble(status = reason),
         clusters = tibble::tibble(status = reason))
  }

  # Need at least 4 cells AND at least 2 different scores to say anything.
  if (nrow(valid) < 4 || length(unique(valid$hotspot_score)) < 2) {
    return(insufficient("insufficient variation or valid cells"))
  }

  # --- STEP 2: build the neighbour list --------------------------------------
  # poly2nb() finds which cells share a border.
  # queen = TRUE means "share a border OR a corner" (8 neighbours).
  nb <- spdep::poly2nb(valid, queen = TRUE)

  # If no cell touches another, the tests cannot run.
  if (!any(spdep::card(nb) > 0)) {
    return(insufficient("no neighbouring valid cells"))
  }

  # --- STEP 3: Moran's I ------------------------------------------------------
  # nb2listw() turns the neighbour list into row-standardised weights
  # (a cell's value is compared with the AVERAGE of its neighbours).
  lw <- spdep::nb2listw(nb, style = "W", zero.policy = TRUE)

  # moran.test() gives the observed Moran's I, the expected value under
  # randomness, the variance, and a p-value.
  # tryCatch() means: if it fails, store NULL instead of crashing the pipeline.
  mi <- tryCatch(
    spdep::moran.test(valid$hotspot_score, lw, zero.policy = TRUE),
    error = function(e) NULL
  )

  if (is.null(mi)) {
    return(insufficient("Moran's I could not be calculated"))
  }

  # --- STEP 4: Getis-Ord Gi* -------------------------------------------------
  # include.self(nb) + style = "B" makes each cell compared with
  # ITSELF PLUS its neighbours (a cell is usually part of its own hotspot).
  # localG() returns a z-score per cell.
  gi <- tryCatch(
    spdep::localG(
      valid$hotspot_score,
      spdep::nb2listw(spdep::include.self(nb), style = "B", zero.policy = TRUE),
      zero.policy = TRUE
    ),
    error = function(e) rep(NA_real_, nrow(valid))
  )

  # Convert each z-score into a two-sided p-value.
  # z = 0 -> p = 1 (not special);  larger |z| -> smaller p (more special).
  pvals <- 2 * stats::pnorm(abs(as.numeric(gi)), lower.tail = FALSE)

  # Benjamini-Hochberg correction: because we test many cells at once,
  # some would look significant by chance alone. This step reduces the
  # number of false positives.
  pvals_bh <- stats::p.adjust(pvals, method = "BH")

  # --- STEP 5: DBSCAN clustering of the best cells ---------------------------
  # Take only the top cells (those at or above the 80th percentile of the score).
  high <- valid |>
    dplyr::filter(hotspot_score >= stats::quantile(hotspot_score,
                                                   cfg$hotspot_percentile,
                                                   names = FALSE))

  # DBSCAN measures distance in metres, so we must project into a
  # coordinate system measured in metres. EPSG:3857 is the common
  # simple choice for this kind of grouping.
  xy <- sf::st_coordinates(
    sf::st_centroid(sf::st_transform(high, 3857))
  )

  # eps is converted from kilometres to metres (x1000).
  clusters <- if (nrow(high) >= cfg$dbscan_min_pts) {
    dbscan::dbscan(xy,
                   eps    = cfg$dbscan_eps_km * 1000,
                   minPts = cfg$dbscan_min_pts)$cluster
  } else {
    rep(NA_integer_, nrow(high))
  }

  # --- STEP 6: package everything into three tidy tables ---------------------
  list(
    moran = tibble::tibble(
      status      = "calculated",
      moran_i     = unname(mi$estimate[[1]]),   # the actual clustering measure
      expected_i  = unname(mi$estimate[[2]]),   # value expected under randomness
      variance    = unname(mi$estimate[[3]]),
      p_value     = mi$p.value,
      valid_cells = nrow(valid)
    ),

    gi = tibble::tibble(
      cell_id                  = valid$cell_id,
      gi_star_z                = as.numeric(gi),
      p_value                  = pvals,
      p_value_bh               = pvals_bh,
      # A significant HIGH cluster: positive z AND corrected p below 0.05
      significant_high_cluster = as.numeric(gi) > 0 & pvals_bh < .05
    ),

    clusters = tibble::tibble(
      cell_id        = high$cell_id,
      dbscan_cluster = clusters
    )
  )
}


# ------------------------------------------------------------
# 10. MAP AND FIGURE HELPERS
# ------------------------------------------------------------

# Draw a CONTINUOUS variable as a choropleth-style map
# (good for mean concentration, richness, and the priority score).
#
# The viridis palette is colour-blind friendly and still readable when
# printed in greyscale, so it is a safe academic choice.
save_map <- function(grid, variable, title, file) {

  p <- ggplot2::ggplot(grid) +
    ggplot2::geom_sf(ggplot2::aes(fill = .data[[variable]]), colour = NA) +
    ggplot2::scale_fill_viridis_c(na.value = "grey90") +   # grey = no data
    ggplot2::labs(title = title, fill = variable,
                  x = "Longitude", y = "Latitude") +
    ggplot2::coord_sf(expand = FALSE) +
    ggplot2::theme_minimal(base_size = 12)

  ggplot2::ggsave(file, p, width = 12, height = 7, dpi = 300)
}


# Draw a YES / NO variable as a three-colour categorical map.
#
# The three categories are deliberately separated:
#   red  = hotspot
#   blue = not a hotspot
#   grey = no paired observation at all
# Keeping "no data" visually distinct prevents a reader from
# mistaking "we did not measure here" for "this area is clean".
save_flag_map <- function(grid, variable, title, file) {

  x <- grid |>
    dplyr::mutate(
      .flag = dplyr::case_when(
        is.na(.data[[variable]]) ~ "No paired observation",  # no data first
        .data[[variable]]          ~ "Hotspot",               # then TRUE
        TRUE                       ~ "Not hotspot"            # everything else
      )
    )

  p <- ggplot2::ggplot(x) +
    ggplot2::geom_sf(ggplot2::aes(fill = .flag), colour = NA) +
    ggplot2::scale_fill_manual(values = c("Hotspot"               = "#b2182b",
                                          "Not hotspot"           = "#d1e5f0",
                                          "No paired observation" = "grey90")) +
    ggplot2::labs(title = title, fill = NULL,
                  x = "Longitude", y = "Latitude") +
    ggplot2::coord_sf(expand = FALSE) +
    ggplot2::theme_minimal(base_size = 12)

  ggplot2::ggsave(file, p, width = 12, height = 7, dpi = 300)
}