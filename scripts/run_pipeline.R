# ============================================================
# MAIN PIPELINE RUNNER
# ============================================================
# HOW TO RUN THE WHOLE PROJECT
#
#   From an R console (with the project open):
#       source("scripts/run_pipeline.R")
#
#   Or from a terminal:
#       Rscript scripts/run_pipeline.R
#
# WHAT THIS FILE DOES
#   Rather than repeating eleven blocks of code, it LISTS the step files
#   in order and runs each one with source().
#
# WHY BUILD THE LIST LIKE THIS?
#   sprintf() writes the file names using the same numbering and naming
#   pattern as the files on disk, so adding or reordering a step means
#   changing one line instead of editing the whole script.
#   1:11 gives the numbers 1 to 11; the c(...) supplies the words.
# ============================================================


# ---- Build the ordered list of pipeline step files ---------------------------
steps <- sprintf(
  "R/%02d_%s.R",                       # %02d = zero-padded number, e.g. 07
  1:11,                                # the step numbers
  c("download_data",                   # step 1
    "clean_microplastics",             # step 2
    "clean_biodiversity",              # step 3
    "create_grid",                     # step 4
    "spatial_join",                    # step 5
    "pollution_analysis",              # step 6
    "biodiversity_analysis",           # step 7
    "hotspot_analysis",                # step 8
    "spatial_statistics",              # step 9
    "sensitivity_analysis",            # step 10
    "visualization")                   # step 11
)


# ---- Load settings and helper functions, then run step 1 -------------------
source("config.R")
source("R/utils.R")
ensure_dirs()
source(steps[[1]])


# ---- Check that both official datasets are present --------------------------
# This check sits HERE, after the documentation step, so that the
# provenance files are always written even when the data is missing.
#
# file.exists() answers "is this file there?" with TRUE or FALSE.
# The || operator means "either one missing". We then stop with a clear
# instruction instead of letting a later step fail with a cryptic error.
if (!file.exists(cfg$paths$microplastics_raw) ||
    !file.exists(cfg$paths$biodiversity_raw)) {
  stop("Official raw CSV inputs are missing. See data/raw/source_metadata.csv and README.md. No analysis outputs were created.",
       call. = FALSE)
}


# ---- Run steps 2 to 11 in order ----------------------------------------------
# seq_along() gives the positions of the remaining steps.
# The [[ ]] extracts one element at a time, which is what source() needs.
# message() prints progress so a long run is not a silent wait.
for (i in seq_along(steps[-1])) {
  message(sprintf("[%d/10] %s", i, basename(steps[-1][[i]])))
  source(steps[-1][[i]])
}

message("Pipeline completed with official input files.")