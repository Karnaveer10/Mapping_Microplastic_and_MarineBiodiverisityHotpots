# ============================================================
# STEP 0 - CONFIGURATION
# ============================================================
# This file holds every setting used by the analysis.
#
# WHY A SEPARATE CONFIG FILE?
#   Changing the grid size, the study area, or the hotspot threshold
#   should NOT require editing the analysis code. Keeping all settings
#   in one place means the code stays readable and the analysis stays
#   reproducible - anyone can see exactly which parameters were used.
#
# The whole project shares these settings through one object called `cfg`.
# A list in R is written like list(name = value, name2 = value2) and can
# hold different types of values together - numbers, text, and even
# other lists.
# ============================================================


# Good practice: do not turn text into factors automatically.
# (Factors were an old R default and usually cause confusion for beginners.)
options(stringsAsFactors = FALSE)


# ------------------------------------------------------------
# cfg = the master settings list for the whole project
# ------------------------------------------------------------
cfg <- list(

  # ----------------------------------------------------------
  # COORDINATE REFERENCE SYSTEM (CRS)
  # ----------------------------------------------------------
  # 4326 is the EPSG code for WGS84 - the lat/lon system that
  # Google Maps, OBIS and NOAA all use. Because both datasets
  # arrive in WGS84, no reprojection is needed before the join.
  crs = 4326,

  # ----------------------------------------------------------
  # STUDY AREA (the bounding box)
  # ----------------------------------------------------------
  # The documented extent from the proposal: 20-147 degrees East
  # and 60-30 degrees South-to-North.
  #
  # Named values (xmin/ymin/xmax/ymax) are used instead of a plain
  # c(20, -60, 147, 30) so that nobody has to remember the order.
  #   xmin = 20    western edge  (East Africa / Arabian Sea)
  #   ymin = -60   southern edge (Southern Ocean)
  #   xmax = 147   eastern edge  (north of Australia)
  #   ymax = 30    northern edge (Arabian Sea / Gulf region)
  #
  # NOTE: this is a rectangle, not a land-masked ocean polygon.
  study_bbox = c(xmin = 20,
                 ymin = -60,
                 xmax = 147,
                 ymax = 30),

  # ----------------------------------------------------------
  # GRID RESOLUTION (main analysis)
  # ----------------------------------------------------------
  # 0.5 degrees x 0.5 degrees at the equator is roughly
  # 55 km x 55 km. Small enough to show coastal hotspots,
  # large enough that a cell usually gets at least one sample.
  grid_degrees = 0.5,

  # ----------------------------------------------------------
  # HOTSPOT THRESHOLD (main analysis)
  # ----------------------------------------------------------
  # A cell is called a hotspot when its value is above the 80th
  # percentile - in plain English, the top 20% of cells that have data.
  #
  # WHY A PERCENTILE AND NOT A FIXED NUMBER?
  #   Because the two datasets are very different in size and spread.
  #   A percentile always produces the same PROPORTION of hotspots,
  #   which makes the two layers directly comparable and makes the
  #   result reproducible on any dataset.
  hotspot_percentile = 0.80,

  # ----------------------------------------------------------
  # THRESHOLD DOMAIN ("all_observed" vs "co_sampled")
  # ----------------------------------------------------------
  # "all_observed" : thresholds computed over all cells with that layer
  #                  (Pollution over ~198 cells, Richness over ~15,533 cells).
  # "co_sampled"   : thresholds computed strictly over cells where BOTH
  #                  layers were observed (144 cells on both sides).
  #                  This completely solves the unequal sample size problem!
  hotspot_domain = "all_observed",

  # ----------------------------------------------------------
  # SENSITIVITY ANALYSIS settings
  # ----------------------------------------------------------
  # A single threshold can be criticised as arbitrary, so we repeat
  # the whole analysis with stricter and looser thresholds.
  # 0.70 = top 30% of cells (more generous)
  # 0.80 = top 20% of cells (our main answer)
  # 0.90 = top 10% of cells (very strict)
  sensitivity_thresholds = c(0.70, 0.80, 0.90),

  # We also repeat it on a coarser grid to check that the pattern
  # is not just an artefact of the 0.5 degree cell size.
  #   0.5 = fine grid   (main analysis)
  #   1.0 = coarse grid (robustness check)
  sensitivity_resolutions = c(0.5, 1.0),

  # ----------------------------------------------------------
  # RANKING AND CLUSTERING
  # ----------------------------------------------------------
  # How many of the highest-priority cells to list in the final table.
  top_n = 20,

  # DBSCAN works in metres, so the distance is written in kilometres
  # here (clearer for a human reader) and multiplied by 1000 in the code.
  #   eps_km    : two cells are "neighbours" if their centres are
  #               within this distance of each other.
  #   min_pts   : a group needs at least this many cells to count
  #               as a real cluster rather than noise.
  dbscan_eps_km = 150,
  dbscan_min_pts = 3,

  # ----------------------------------------------------------
  # FILE PATHS
  # ----------------------------------------------------------
  # Stored here instead of being typed inside each script, so a file
  # can be renamed in ONE place only.
  # Set microplastics_raw to "data/raw/noaa_oisst_marine_heatwaves.csv" for continuous
  # 100% basin-wide coverage (NOAA OISST / Marine Heatwaves), or
  # "data/raw/noaa_marine_microplastics.csv" for cruise net-tows.
  paths = list(
    microplastics_raw = "data/raw/noaa_oisst_marine_heatwaves.csv",
    biodiversity_raw  = "data/raw/obis_indian_ocean_occurrences.csv",
    metadata          = "data/raw/source_metadata.csv"
  ),

  # ----------------------------------------------------------
  # DATA SOURCE LINKS (used in the report and citations)
  # ----------------------------------------------------------
  sources = list(
    microplastics = "https://www.ncei.noaa.gov/products/optimum-interpolation-sst",
    biodiversity  = "https://obis.org/data/access/",
    obis_api      = "https://api.obis.org/occurrence"
  )
)