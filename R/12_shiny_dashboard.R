# ============================================================
# STEP 12 — MINIMAL, FAST INTERACTIVE SHINY DASHBOARD
# ============================================================
# WHAT THIS DOES
#   A clean, streamlined web dashboard to explore marine hotspots:
#     1. Pollution Hotspots
#     2. Biodiversity Hotspots
#     3. Effective Hotspots (dual overlap)
#   With instant threshold adjustment and blazing-fast canvas rendering.
# ============================================================

# ---- 0. Package loading & project root ----------------------------------------
project_root <- if (file.exists("config.R")) {
  normalizePath(getwd())
} else if (file.exists(file.path("..", "config.R"))) {
  normalizePath("..")
} else {
  candidate_dir <- tryCatch(
    dirname(normalizePath(sys.frame(0)$ofile)),
    error = function(e) getwd()
  )
  if (file.exists(file.path(candidate_dir, "config.R"))) {
    normalizePath(candidate_dir)
  } else if (file.exists(file.path(candidate_dir, "..", "config.R"))) {
    normalizePath(file.path(candidate_dir, ".."))
  } else {
    normalizePath(getwd())
  }
}
setwd(project_root)

project_lib <- file.path(project_root, "renv/library/R-4.6")
if (dir.exists(project_lib)) {
  .libPaths(c(normalizePath(project_lib), .libPaths()))
}

dashboard_packages <- c("shiny", "bslib", "leaflet", "DT", "dplyr", "sf", "readr", "scales")
invisible(lapply(dashboard_packages, library, character.only = TRUE))

source(file.path(project_root, "config.R"))
source(file.path(project_root, "R/utils.R"))

# ---- 1. Load data -------------------------------------------------------------
base_grid <- readRDS(file.path(project_root, "data/processed/grid_analysis.rds"))

# Fast scoring function keeping only necessary calculation
rescore <- function(threshold) {
  score_hotspots(base_grid, threshold = threshold, domain = "all_observed")
}

# ---- 2. UI (Clean, Minimal Theme) ---------------------------------------------
ui <- bslib::page_navbar(
  title = "Marine Hotspots Explorer",
  theme = bslib::bs_theme(
    version   = 5,
    bootswatch = "flatly",
    primary   = "#2c3e50",
    secondary = "#18bc9c"
  ),

  # ---- TAB 1: Map Explorer ----
  bslib::nav_panel(
    title = "Map Explorer",
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        width = 300,
        tags$h5("Hotspot Settings", class = "fw-bold mb-3"),

        shiny::selectInput(
          "map_layer",
          label   = "Select Hotspot Layer:",
          choices = c(
            "Effective Hotspots (Both)" = "effective_hotspot",
            "Pollution Hotspots"        = "pollution_hotspot",
            "Biodiversity Hotspots"     = "biodiversity_hotspot"
          ),
          selected = "effective_hotspot"
        ),

        tags$hr(),

        shiny::sliderInput(
          "threshold",
          label = "Percentile Cut-off:",
          min   = 0.60,
          max   = 0.95,
          value = 0.80,
          step  = 0.05,
          ticks = TRUE,
          width = "100%"
        ),
        tags$p(
          class = "text-muted small",
          "Filters cells in the top percentile. Effective hotspots require both layers to exceed this cut-off."
        ),

        tags$hr(),
        tags$div(
          class = "card bg-light p-3 border-0",
          tags$span(class = "text-muted small text-uppercase fw-bold", "Active Hotspots"),
          tags$h3(textOutput("active_count"), class = "fw-bold text-primary my-1"),
          tags$span(class = "text-muted small", "Matching cells displayed on map")
        )
      ),

      bslib::card(
        full_screen = TRUE,
        style = "border:none; padding:0;",
        leaflet::leafletOutput("main_map", height = "750px")
      )
    )
  ),

  # ---- TAB 2: Ranked Table ----
  bslib::nav_panel(
    title = "Data Table",
    bslib::card(
      full_screen = TRUE,
      style = "padding:20px; border:none;",
      bslib::card_header(
        class = "bg-white border-bottom pb-3 mb-2 d-flex justify-content-between align-items-center",
        tags$h5("Ranked Hotspot Cells", class = "m-0 fw-bold"),
        shiny::downloadButton("download_table", "Export CSV", class = "btn btn-outline-secondary btn-sm")
      ),
      DT::dataTableOutput("hotspot_table", height = "650px")
    )
  )
)

# ---- 3. Server ---------------------------------------------------------------
server <- function(input, output, session) {

  # Reactive scored dataset
  scored <- shiny::reactive({
    rescore(input$threshold)
  })

  # Filtered active hotspot layer
  active_subset <- shiny::reactive({
    g <- scored()
    layer <- input$map_layer
    g[which(g[[layer]] == TRUE), ]
  })

  # KPI text count
  output$active_count <- shiny::renderText({
    sub <- active_subset()
    format(nrow(sub), big.mark = ",")
  })

  # Render Leaflet base map once (100% free tiles with zero API keys required)
  output$main_map <- leaflet::renderLeaflet({
    leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE)) |>
      leaflet::addTiles(
        urlTemplate = "https://server.arcgisonline.com/ArcGIS/rest/services/Ocean/World_Ocean_Base/MapServer/tile/{z}/{y}/{x}",
        attribution = "Tiles &copy; Esri &mdash; Sources: GEBCO, NOAA, CHS, OSU, UNH, CSUMB, National Geographic, DeLorme, NAVTEQ, and Esri",
        group = "Esri Ocean"
      ) |>
      leaflet::addTiles(
        urlTemplate = "https://server.arcgisonline.com/ArcGIS/rest/services/Ocean/World_Ocean_Reference/MapServer/tile/{z}/{y}/{x}",
        group = "Esri Ocean"
      ) |>
      leaflet::addTiles(
        group = "OpenStreetMap"
      ) |>
      leaflet::addLayersControl(
        baseGroups = c("Esri Ocean", "OpenStreetMap"),
        position = "topright"
      ) |>
      leaflet::setView(lng = 80, lat = -5, zoom = 4)
  })

  # Dynamic update on threshold or layer change
  shiny::observe({
    sub   <- active_subset()
    layer <- input$map_layer

    proxy <- leaflet::leafletProxy("main_map", session)
    proxy |>
      leaflet::clearShapes() |>
      leaflet::clearControls()

    if (nrow(sub) == 0) return()

    # Layer styling
    if (layer == "effective_hotspot") {
      fill_col   <- "#e74c3c"
      legend_lbl <- "Effective Hotspot (Dual)"
    } else if (layer == "pollution_hotspot") {
      fill_col   <- "#e67e22"
      legend_lbl <- "Pollution Hotspot"
    } else {
      fill_col   <- "#2980b9"
      legend_lbl <- "Biodiversity Hotspot"
    }

    popup_text <- paste0(
      "<div style='font-family:sans-serif;font-size:12px;'>",
      "<b>Cell: ", sub$cell_id, "</b><br>",
      "<hr style='margin:4px 0;'>",
      "Priority Score: <b>", ifelse(is.na(sub$hotspot_score), "NA", round(sub$hotspot_score, 4)), "</b><br>",
      "Microplastic Conc: <b>", ifelse(is.na(sub$mean_microplastic), "NA", round(sub$mean_microplastic, 3)), "</b><br>",
      "Species Richness: <b>", ifelse(is.na(sub$species_richness), "NA", sub$species_richness), "</b>",
      "</div>"
    )

    proxy |>
      leaflet::addPolygons(
        data        = sub,
        fillColor   = fill_col,
        fillOpacity = 0.7,
        color       = fill_col,
        weight      = 0.8,
        popup       = popup_text,
        label       = paste0(sub$cell_id, " (Score: ", round(sub$hotspot_score, 3), ")"),
        labelOptions = leaflet::labelOptions(
          style = list("font-size" = "11px"),
          direction = "auto"
        )
      ) |>
      leaflet::addLegend(
        position = "bottomright",
        colors   = fill_col,
        labels   = paste0(legend_lbl, " (", nrow(sub), " cells)"),
        opacity  = 0.8
      )
  })

  # Table Output
  table_data <- shiny::reactive({
    sub <- active_subset()
    sub |>
      sf::st_drop_geometry() |>
      dplyr::arrange(dplyr::desc(hotspot_score)) |>
      dplyr::select(
        Cell_ID          = cell_id,
        Priority_Score   = hotspot_score,
        MP_Concentration = mean_microplastic,
        Species_Richness = species_richness,
        P_Rank           = P,
        B_Rank           = B
      ) |>
      dplyr::mutate(
        across(c(Priority_Score, MP_Concentration, P_Rank, B_Rank), ~round(., 4))
      )
  })

  output$hotspot_table <- DT::renderDataTable({
    DT::datatable(
      table_data(),
      rownames = FALSE,
      options  = list(pageLength = 20, scrollX = TRUE, dom = "frtip"),
      class    = "table table-hover table-striped table-sm"
    )
  })

  output$download_table <- shiny::downloadHandler(
    filename = function() {
      paste0("hotspots_", input$map_layer, "_th", input$threshold * 100, ".csv")
    },
    content = function(file) {
      readr::write_csv(table_data(), file)
    }
  )
}

# ---- 4. Launch App -----------------------------------------------------------
shiny::shinyApp(ui = ui, server = server)
