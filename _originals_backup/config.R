options(stringsAsFactors = FALSE)

# All geographic bounds are inclusive and deliberately documented. They cover the
# Indian Ocean basin and adjacent marginal seas used in the proposal.
cfg <- list(
  crs = 4326,
  study_bbox = c(xmin = 20, ymin = -60, xmax = 147, ymax = 30),
  grid_degrees = 0.5,
  hotspot_percentile = 0.80,
  sensitivity_thresholds = c(0.70, 0.80, 0.90),
  sensitivity_resolutions = c(0.5, 1.0),
  top_n = 20,
  dbscan_eps_km = 150,
  dbscan_min_pts = 3,
  paths = list(
    microplastics_raw = "data/raw/noaa_marine_microplastics.csv",
    biodiversity_raw = "data/raw/obis_indian_ocean_occurrences.csv",
    metadata = "data/raw/source_metadata.csv"
  ),
  sources = list(
    microplastics = "https://www.ncei.noaa.gov/products/microplastics",
    biodiversity = "https://obis.org/data/access/",
    obis_api = "https://api.obis.org/occurrence"
  )
)
