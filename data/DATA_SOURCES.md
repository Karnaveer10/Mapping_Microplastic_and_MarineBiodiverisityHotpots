# Data sources and provenance

## NOAA NCEI Marine Microplastics

- Provider: NOAA National Centers for Environmental Information.
- Official access: https://www.ncei.noaa.gov/products/microplastics
- Expected local file: `data/raw/noaa_marine_microplastics.csv`.
- Required analysis fields: longitude, latitude, numeric concentration.
- Retain where provided: record identifier, date/year, depth, sample type, sampling method, analytical method, original units, and data provider.
- Processing: coordinate validation, Indian Ocean extent filtering, invalid or missing concentration removal, and exact duplicate removal on coordinate and concentration fields. The pipeline does not automatically remove legitimate extreme concentrations.
- Important caveat: NOAA documents methodological heterogeneity across contributing datasets; compare concentrations only with this limitation stated.

## OBIS / IndOBIS marine occurrences

- Provider: Ocean Biodiversity Information System.
- Official access: https://obis.org/data/access/
- API base documented by OBIS: https://api.obis.org/occurrence
- Expected local file: `data/raw/obis_indian_ocean_occurrences.csv`.
- Required analysis fields: decimal longitude, decimal latitude, scientific name.
- Retain where provided: occurrenceID, eventID, date/year, taxonomic group, kingdom, phylum, class, order, family, genus, and basis of record.
- Processing: coordinate validation, Indian Ocean extent filtering, missing species-identity removal, and exact duplicate removal on coordinate and scientific name fields.

## Access log

At each use, fill `data/raw/source_metadata.csv` with the actual export URL or query, access date, original filename, record count, filters, and unit information. No raw observation file is included in this repository.

---

## Alternative and Continuous Global Pollution Datasets

### 1. Van Sebille et al. Global Microplastic Circulation Model (Continuous Layer)
- **Reference**: Van Sebille et al. (2015), *A global inventory of small floating plastic debris*, Environmental Research Letters 10(12), 124006.
- **Provider**: Imperial College London / Utrecht University / Global Drifter Program.
- **Format**: Global gridded raster/table ($0.5^\circ \times 0.5^\circ$ or $1.0^\circ \times 1.0^\circ$).
- **Content**: Modeled microplastic count density (pieces/km²) and mass density (g/km²) calculated from Lagrangian ocean circulation models (Maximenko and van Sebille drift trajectories) calibrated against empirical net tows.
- **Why it overcomes empirical sampling gaps**: Provides continuous values across all ocean cells, allowing joint comparison with continuous biodiversity surfaces without sample-size imbalance.

### 2. Eriksen et al. Global Net Tows (Empirical Dataset)
- **Reference**: Eriksen et al. (2014 & 2023 update), *Plastic Pollution in the World's Oceans*, PLOS ONE.
- **Provider**: 5 Gyres Institute.
- **Content**: Over 22,000+ empirical manta/neuston net tows across global gyres and coastal waters, expanding field sample density across the Indian Ocean basin.
