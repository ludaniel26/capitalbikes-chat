# ui.R -- layout only. Data, helpers and design tokens live in global.R.

ui <- navbarPage(
  title = "Capital Bikes",
  id = "nav",
  collapsible = TRUE,
  theme = bs_theme(version = 5, primary = RED, secondary = TEAL),

  header = tags$head(
    tags$link(rel = "stylesheet", href = "capital.css"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1")
  ),


  # ------------------------------------------------------------------ About

  tabPanel(
    "About",
    div(
      class = "container-fluid",
      div(
        class = "hero",
        img(src = "CapitalBikeshareStationDockedBikes.jpg", alt = "Capital Bikeshare bikes docked at a station"),
        div(
          class = "hero__overlay",
          h1(class = "hero__title", "Every ride DC took in 2023"),
          p(class = "hero__sub",
            "Find a dock, plan a route, and see how weather and season moved ",
            "3.6 million Capital Bikeshare trips across Washington.")
        )
      ),

      div(
        class = "tilerow",
        stat_tile("Stations mapped", format(nrow(stations), big.mark = ","), accent = "ink"),
        stat_tile("Bikes docked now", format(sum(stations$total_bikes_available), big.mark = ","),
                  sub = "regular and e-bikes", accent = "red"),
        stat_tile("Days of weather", format(nrow(weather_data), big.mark = ","),
                  sub = "paired with ride data", accent = "teal"),
        stat_tile("Busiest station", "Union Station",
                  sub = "top start, 11 of 12 months", accent = "gold")
      ),

      h3(class = "pagehead__title", style = "font-size:1.35rem;margin-bottom:.7rem;", "What you can do here"),

      fluidRow(
        column(3, div(class = "feature",
          div(class = "feature__tag", "Tab 02"),
          h4(class = "feature__name", "Bike Station Map"),
          p(class = "feature__body",
            "Search any of the 778 docks and see how many regular bikes and e-bikes are waiting. ",
            "Marker size and colour track how well stocked each station is.")
        )),
        column(3, div(class = "feature",
          div(class = "feature__tag", "Tab 03"),
          h4(class = "feature__name", "Bike Router"),
          p(class = "feature__body",
            "Pick a start and an end dock and get a cycling route drawn on the map, ",
            "with riding time and the elevation you will climb or drop.")
        )),
        column(3, div(class = "feature",
          div(class = "feature__tag", "Tab 04"),
          h4(class = "feature__name", "Weather Trends"),
          p(class = "feature__body",
            "Filter by date and temperature to see when Washington rides longest, ",
            "and what rain, snow and freezing rain do to trip length.")
        )),
        column(3, div(class = "feature",
          div(class = "feature__tag", "Tab 05"),
          h4(class = "feature__name", "Station Frequency"),
          p(class = "feature__body",
            "Compare the ten busiest start stations for any month of 2023, ",
            "and read what there is to see and do around eighteen of them.")
        ))
      ),

      div(class = "panel-card", style = "margin-top:1.4rem;",
        div(class = "panel-card__title", "About this project"),
        div(class = "colophon",
          p(HTML(paste0(
            "Built by <strong>Daniel Lu</strong>, <strong>Ava GianGrasso</strong> and ",
            "<strong>Hatcher Cook</strong> at Washington and Lee University. Daniel and Ava ",
            "are junior neuroscience majors; Hatcher is a senior biology major."
          ))),
          p(HTML(paste0(
            "Trip data covers all of 2023 and comes from the Kaggle dataset ",
            "<em>Capital bikeshare dataset 2020/05 – 2024/08</em>. Routing and travel times ",
            "come from the Google Maps Directions and Distance Matrix APIs; elevation from ",
            "the <code>elevatr</code> package. Maps are drawn with Leaflet over OpenStreetMap."
          )))
        )
      )
    )
  ),


  # -------------------------------------------------------- Bike Station Map

  tabPanel(
    "Bike Station Map",
    div(
      class = "container-fluid",
      page_head(
        "Tab 02 / Docks",
        "Find a station",
        paste("Search any of the", format(nrow(stations), big.mark = ","),
              "Capital Bikeshare docks in the system. Larger, greener markers hold more bikes;",
              "small red ones are nearly empty.")
      ),
      sidebarLayout(
        sidebarPanel(
          width = 3,
          selectizeInput(
            "name",
            label = "Station",
            choices = NULL,
            options = list(placeholder = "Type to search stations")
          ),
          div(style = "margin-top:.9rem;", uiOutput("stationLegend"))
        ),
        mainPanel(
          width = 9,
          uiOutput("stationStats"),
          div(class = "panel-card",
            div(class = "panel-card__title", "Search station locations by map"),
            leafletOutput("stationMap", height = "520px")
          )
        )
      )
    )
  ),


  # ------------------------------------------------------------ Bike Router

  tabPanel(
    "Bike Router",
    div(
      class = "container-fluid",
      page_head(
        "Tab 03 / Routing",
        "Plan a ride",
        paste("Choose where you are starting and where you are headed. The route follows",
              "cycling directions, and the summary shows how long it should take and how much",
              "you will climb along the way.")
      ),
      sidebarLayout(
        sidebarPanel(
          width = 3,
          selectizeInput("origin", "Start", choices = NULL,
                         options = list(placeholder = "Pick a start dock")),
          selectizeInput("destination", "Destination", choices = NULL,
                         options = list(placeholder = "Pick an end dock")),
          div(style = "margin-top:.9rem;", actionButton("route", "Plan route", class = "btn-primary")),
          div(style = "margin-top:1rem;", uiOutput("routeMessage"))
        ),
        mainPanel(
          width = 9,
          uiOutput("routeStats"),
          div(class = "panel-card",
            div(class = "panel-card__title", "Route"),
            leafletOutput("map", height = "520px")
          )
        )
      )
    )
  ),


  # --------------------------------------------------------- Weather Trends

  tabPanel(
    "Weather Trends",
    div(
      class = "container-fluid",
      page_head(
        "Tab 04 / Conditions",
        "When Washington rides",
        paste("Ride length against date, temperature and precipitation across 2023.",
              "Narrow the sliders to isolate a season or a temperature band and watch the",
              "trend line respond.")
      ),
      sidebarLayout(
        sidebarPanel(
          width = 3,
          radioButtons("plotType", "Date chart style",
                       c("Scatter" = "p", "Bars" = "b")),
          sliderInput("date_slider", "Date range",
                      min = as.Date("2023-01-01"), max = as.Date("2023-12-31"),
                      value = c(as.Date("2023-01-01"), as.Date("2023-12-31")),
                      timeFormat = "%b %d"),
          sliderInput("temp_slider", "Average temperature (°F)",
                      min = 32, max = 90, value = c(32, 90))
        ),
        mainPanel(
          width = 9,
          uiOutput("weatherStats"),
          div(class = "panel-card",
            div(class = "panel-card__title", "Ride duration over the year"),
            plotlyOutput("dateduration", height = "330px")
          ),
          div(class = "panel-card",
            div(class = "panel-card__title", "Ride duration against temperature"),
            plotlyOutput("tempduration", height = "330px")
          ),
          div(class = "panel-card",
            div(class = "panel-card__title", "Ride duration by precipitation type"),
            plotOutput("precipduration", height = "300px")
          )
        )
      )
    )
  ),


  # ------------------------------------------------------- Station Frequency

  tabPanel(
    "Station Frequency",
    div(
      class = "container-fluid",
      page_head(
        "Tab 05 / Demand",
        "The busiest docks, month by month",
        paste("The ten most used start stations for any month of 2023. Union Station led",
              "eleven of the twelve months, peaking at 5,340 departures in October.",
              "Search a station below to read what is nearby.")
      ),
      sidebarLayout(
        sidebarPanel(
          width = 3,
          selectInput("selectMonth", "Month", choices = MONTHS, selected = "January"),
          hr(),
          textInput("stationName", "Station notes",
                    placeholder = "Try: union, lincoln, dupont"),
          uiOutput("stationBlurb")
        ),
        mainPanel(
          width = 9,
          uiOutput("freqStats"),
          div(class = "panel-card",
            div(class = "panel-card__title", "Top 10 start stations"),
            plotlyOutput("selectedfreq", height = "480px")
          )
        )
      )
    )
  ),
  
  
  # ------------------------------------------------------- AI Chat
  
  tabPanel(
    "Ask CapRi!",
    div(
      class = "container-fluid",
      page_head(
        "Tab 06 / CapRi AI Assistant",
        "Ask about the data",
        paste("Ask a question about 2023 ride patterns, weather or station demand."
          )
      ),
      div(class = "panel-card",
          chat_ui("askdata", height = "460px",
                  messages = list(
                    "Ask me about 2023 ride patterns. For example: *Are rides shorter when it rains?* or *Which month had the longest average rides?*",
                    "CapRi is AI and can make mistakes. Please double-check responses. "
                  ))
      ),
    )
  )
)

ui
