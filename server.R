# server.R -- all reactive logic. Data and helpers come from global.R.

function(input, output, session) {

  # Station lists are pushed from the server so the browser isn't sent 778
  # <option> tags three times in the page source.
  updateSelectizeInput(session, "name", choices = station_choices,
                       selected = station_choices[1], server = TRUE)
  updateSelectizeInput(session, "origin", choices = station_choices, server = TRUE)
  updateSelectizeInput(session, "destination", choices = station_choices, server = TRUE)


  # ====================================================== Bike Station Map ==

  selected_station <- reactive({
    req(input$name)
    stations[stations$name == input$name, ][1, ]
  })

  output$stationStats <- renderUI({
    s <- selected_station()
    req(nrow(s) == 1, !is.na(s$name))

    div(
      class = "tilerow",
      stat_tile("Regular bikes", s$num_bikes_available, accent = "ink"),
      stat_tile("E-bikes", s$num_ebikes_available, accent = "teal"),
      stat_tile("Total available", s$total_bikes_available,
                sub = as.character(s$dock_band), accent = "red"),
      stat_tile("Coordinates",
                sprintf("%.3f, %.3f", s$latitude, s$longitude),
                sub = "latitude, longitude", accent = "gold")
    )
  })

  output$stationLegend <- renderUI({
    div(
      class = "blurb__hint",
      div(style = "font-weight:600;color:#0E1620;margin-bottom:.4rem;", "Marker colour"),
      tags$div(style = "display:flex;align-items:center;gap:.5rem;margin-bottom:.25rem;",
               tags$span(style = "width:10px;height:10px;border-radius:50%;background:#D2232A;display:inline-block;"),
               "5 bikes or fewer"),
      tags$div(style = "display:flex;align-items:center;gap:.5rem;margin-bottom:.25rem;",
               tags$span(style = "width:10px;height:10px;border-radius:50%;background:#C8A44D;display:inline-block;"),
               "6 to 15 bikes"),
      tags$div(style = "display:flex;align-items:center;gap:.5rem;",
               tags$span(style = "width:10px;height:10px;border-radius:50%;background:#10707E;display:inline-block;"),
               "More than 15 bikes")
    )
  })

  # Drawn once. Panning to a new station uses leafletProxy instead of redrawing
  # 778 markers every time the dropdown changes.
  output$stationMap <- renderLeaflet({
    pal_colour <- ifelse(stations$total_bikes_available <= 5, RED,
                  ifelse(stations$total_bikes_available <= 15, GOLD, TEAL))

    leaflet() %>%
      addProviderTiles(providers$CartoDB.Positron, group = "Street") %>%
      addProviderTiles(providers$Esri.WorldImagery, group = "Satellite") %>%
      addCircleMarkers(
        data = stations,
        lat = ~latitude, lng = ~longitude,
        clusterOptions = markerClusterOptions(),
        color = pal_colour,
        fillColor = pal_colour,
        fillOpacity = .75,
        weight = 1.5,
        # Square-root scaling keeps the busiest docks from swamping the map.
        radius = ~pmax(4, sqrt(total_bikes_available) * 2.6),
        group = "Stations",
        popup = ~paste0(
          "<strong>", name, "</strong><br/>",
          "Regular bikes: ", num_bikes_available, "<br/>",
          "E-bikes: ", num_ebikes_available, "<br/>",
          "Total: ", total_bikes_available
        )
      ) %>%
      addLayersControl(
        baseGroups = c("Street", "Satellite"),
        overlayGroups = "Stations",
        position = "topright"
      ) %>%
      setView(lng = mean(stations$longitude), lat = mean(stations$latitude), zoom = 12)
  })

  observeEvent(selected_station(), {
    s <- selected_station()
    req(nrow(s) == 1, !is.na(s$latitude))

    leafletProxy("stationMap") %>%
      # Zoom 16 shows the block and its surroundings. The original zoom of 20
      # was so close the map lost all context.
      setView(lng = s$longitude, lat = s$latitude, zoom = 16)
  })


  # ============================================================ Bike Router ==

  route_result <- reactiveVal(NULL)
  route_error  <- reactiveVal(NULL)

  output$routeMessage <- renderUI({
    msg <- route_error()
    if (is.null(msg)) return(NULL)
    div(class = "notice", msg)
  })

  output$routeStats <- renderUI({
    r <- route_result()
    if (is.null(r)) return(NULL)

    div(
      class = "tilerow",
      stat_tile("Riding time", r$time, accent = "red"),
      stat_tile("Elevation change", r$elevation,
                sub = if (r$elev_raw >= 0) "net climb" else "net descent", accent = "teal"),
      stat_tile("From", r$origin_name, accent = "ink"),
      stat_tile("To", r$dest_name, accent = "gold")
    )
  })

  output$map <- renderLeaflet({
    leaflet() %>%
      addProviderTiles(providers$CartoDB.Positron, group = "Street") %>%
      addProviderTiles(providers$Esri.WorldImagery, group = "Satellite") %>%
      addLayersControl(baseGroups = c("Street", "Satellite"), position = "topright") %>%
      setView(lng = mean(stations$longitude), lat = mean(stations$latitude), zoom = 12)
  })

  observeEvent(input$route, {
    route_error(NULL)

    if (!nzchar(MAPS_API_KEY)) {
      route_error("Route planning is switched off: this server has no Google Maps key configured.")
      return(invisible(NULL))
    }
    if (!isTruthy(input$origin) || !isTruthy(input$destination)) {
      route_error("Pick both a start and a destination, then plan the route.")
      return(invisible(NULL))
    }
    if (identical(input$origin, input$destination)) {
      route_error("Start and destination are the same dock. Choose two different stations.")
      return(invisible(NULL))
    }

    origin      <- stations[stations$name == input$origin, ][1, ]
    destination <- stations[stations$name == input$destination, ][1, ]

    # Any failure here is a network or API problem, not a bug in the app, so it
    # becomes a message in the sidebar rather than a crashed session.
    outcome <- tryCatch({

      directions <- mp_directions(
        origin      = c(origin$longitude, origin$latitude),
        destination = c(destination$longitude, destination$latitude),
        key         = MAPS_API_KEY,
        mode        = "bicycling",
        alternatives = FALSE
      )

      route <- mp_get_routes(directions)

      timing <- gmapsdistance(
        origin      = paste(origin$latitude, origin$longitude, sep = ","),
        destination = paste(destination$latitude, destination$longitude, sep = ","),
        mode        = "bicycling",
        key         = MAPS_API_KEY
      )

      secs <- as.numeric(timing$Time)
      pretty_time <- if (is.na(secs)) {
        "Unavailable"
      } else if (secs < 3600) {
        sprintf("%d min", round(secs / 60))
      } else {
        sprintf("%dh %dm", secs %/% 3600, (secs %% 3600) %/% 60)
      }

      elevation <- get_elev_point(
        data.frame(x = c(origin$longitude, destination$longitude),
                   y = c(origin$latitude,  destination$latitude)),
        prj = "EPSG:4326", units = "feet"
      )
      change <- diff(elevation$elevation)

      list(
        route       = route,
        time        = pretty_time,
        elevation   = sprintf("%+.0f ft", change),
        elev_raw    = change,
        origin_name = origin$name,
        dest_name   = destination$name
      )

    }, error = function(e) {
      route_error(paste0(
        "The routing service could not return a route just now. ",
        "It reported: ", conditionMessage(e)
      ))
      NULL
    })

    if (is.null(outcome)) return(invisible(NULL))
    route_result(outcome)

    bikeIcon <- makeIcon(
      iconUrl = "https://i.postimg.cc/4xyRN8t9/bikeicon.png",
      iconWidth = 30, iconHeight = 30
    )

    leafletProxy("map") %>%
      clearShapes() %>%
      clearMarkers() %>%
      addPolylines(data = outcome$route, color = RED, weight = 6, opacity = .85) %>%
      addMarkers(
        lng = c(origin$longitude, destination$longitude),
        lat = c(origin$latitude,  destination$latitude),
        icon = bikeIcon,
        label = c(origin$name, destination$name)
      ) %>%
      fitBounds(
        lng1 = min(origin$longitude, destination$longitude),
        lat1 = min(origin$latitude,  destination$latitude),
        lng2 = max(origin$longitude, destination$longitude),
        lat2 = max(origin$latitude,  destination$latitude)
      )
  })


  # ========================================================= Weather Trends ==

  filtered_date_data <- reactive({
    weather_data[weather_data$Date >= input$date_slider[1] &
                 weather_data$Date <= input$date_slider[2], ]
  })

  filtered_temp_data <- reactive({
    weather_data[weather_data$Tempavg >= input$temp_slider[1] &
                 weather_data$Tempavg <= input$temp_slider[2], ]
  })

  output$weatherStats <- renderUI({
    d <- filtered_date_data()
    req(nrow(d) > 0)

    div(
      class = "tilerow",
      stat_tile("Days in range", format(nrow(d), big.mark = ","), accent = "ink"),
      stat_tile("Average ride", sprintf("%.1f min", mean(d$Duration, na.rm = TRUE)), accent = "red"),
      stat_tile("Longest day", sprintf("%.1f min", max(d$Duration, na.rm = TRUE)),
                sub = format(d$Date[which.max(d$Duration)], "%b %d"), accent = "teal"),
      stat_tile("Average temp", sprintf("%.0f °F", mean(d$Tempavg, na.rm = TRUE)), accent = "gold")
    )
  })

  output$dateduration <- renderPlotly({
    d <- filtered_date_data()
    validate(need(nrow(d) > 0, "No days fall inside that date range."))

    p <- ggplot(d, aes(x = Date, y = Duration))

    p <- if (input$plotType == "b") {
      p + geom_col(fill = RED, alpha = .8, width = 1)
    } else {
      p + geom_point(colour = RED, alpha = .55, size = 1.7)
    }

    ggplotly(
      p +
        geom_smooth(method = "loess", formula = y ~ x, colour = INK, linewidth = .8, se = FALSE) +
        labs(x = NULL, y = "Average ride (mins)") +
        theme_capital()
    ) %>% config(displayModeBar = FALSE)
  })

  output$tempduration <- renderPlotly({
    d <- filtered_temp_data()
    validate(need(nrow(d) > 0, "No days fall inside that temperature range."))

    ggplotly(
      ggplot(d, aes(Tempavg, Duration)) +
        geom_point(colour = TEAL, alpha = .6, size = 1.9) +
        geom_smooth(method = "loess", formula = y ~ x, colour = INK, linewidth = .8, se = FALSE) +
        labs(x = "Average temperature (°F)", y = "Average ride (mins)") +
        theme_capital()
    ) %>% config(displayModeBar = FALSE)
  })

  output$precipduration <- renderPlot({
    ggplot(precip_summary, aes(x = preciptype, y = durationavg)) +
      geom_col(fill = c(TEAL, "#7FA8B5", GOLD, INK), width = .62) +
      geom_text(aes(label = sprintf("%.1f", durationavg)),
                vjust = -0.6, size = 3.9, colour = SLATE) +
      scale_y_continuous(expand = expansion(mult = c(0, .16))) +
      labs(x = NULL, y = "Average ride (mins)") +
      theme_capital()
  }, res = 96)


  # ====================================================== Station Frequency ==

  month_freq <- reactive({
    req(input$selectMonth)
    station_freq[[input$selectMonth]]
  })

  output$freqStats <- renderUI({
    d <- month_freq()
    req(nrow(d) > 0)

    div(
      class = "tilerow",
      stat_tile("Busiest dock", d$start_station_name[1],
                sub = paste(format(d$n[1], big.mark = ","), "departures"), accent = "red"),
      stat_tile("Top 10 departures", format(sum(d$n), big.mark = ","),
                sub = paste("in", input$selectMonth), accent = "ink"),
      stat_tile("Gap to second", format(d$n[1] - d$n[2], big.mark = ","),
                sub = "departures ahead", accent = "teal")
    )
  })

  # One plot for all twelve months, replacing twelve near-identical branches.
  output$selectedfreq <- renderPlotly({
    d <- month_freq()
    validate(need(nrow(d) > 0, "No data for that month."))

    # Horizontal bars so station names read straight across instead of being
    # rotated 60 degrees and wrapped onto two lines.
    d$start_station_name <- factor(d$start_station_name, levels = rev(d$start_station_name))
    d$rank_fill <- ifelse(seq_len(nrow(d)) == 1, RED, TEAL)

    p <- ggplot(d, aes(x = start_station_name, y = n,
                       text = paste0(start_station_name, "<br>",
                                     format(n, big.mark = ","), " departures"))) +
      geom_col(fill = d$rank_fill, width = .68) +
      coord_flip() +
      scale_y_continuous(expand = expansion(mult = c(0, .08)),
                         labels = function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)) +
      labs(x = NULL, y = "Departures") +
      theme_capital() +
      theme(panel.grid.major.y = element_blank())

    ggplotly(p, tooltip = "text") %>% config(displayModeBar = FALSE)
  })

  output$stationBlurb <- renderUI({
    if (!isTruthy(input$stationName)) {
      return(div(class = "blurb__empty",
                 "Type a station name to read what is nearby."))
    }

    hit <- match_station(input$stationName)

    if (length(hit) == 1) {
      div(
        class = "blurb",
        div(class = "blurb__name", names(STATION_BLURBS)[hit]),
        p(STATION_BLURBS[[hit]])
      )

    } else if (length(hit) > 1) {
      div(
        class = "blurb__hint",
        "Several stations match. Add a word to narrow it down:",
        tags$ul(class = "blurb__list",
                lapply(names(STATION_BLURBS)[hit], tags$li))
      )

    } else {
      div(
        class = "blurb__hint",
        paste0("No match. Notes have been written for these ",
               length(STATION_BLURBS), " stations:"),
        tags$ul(class = "blurb__list",
                lapply(names(STATION_BLURBS), tags$li))
      )
    }
  })
  
  
  # ====================================================== CapRi AI ==========
  
  # Rate limit: a public app with an API key needs a ceiling.
  question_count <- reactiveVal(0)
  MAX_QUESTIONS <- 15
  
  ask_chat <- reactive({
    req(nzchar(ANTHROPIC_KEY))
    ellmer::chat_anthropic(
      system_prompt = ASSISTANT_PROMPT,
      model = "claude-haiku-4-5-20251001"
    )
  })
  
  observeEvent(input$askdata_user_input, {
    if (!nzchar(ANTHROPIC_KEY)) {
      chat_append("askdata",
                  "The assistant is not configured on this server (no API key set).")
      return()
    }
    
    if (question_count() >= MAX_QUESTIONS) {
      chat_append("askdata",
                  "That's the question limit for this session. Refresh the page to start over.")
      return()
    }
    question_count(question_count() + 1)
    
    tryCatch({
      stream <- ask_chat()$stream_async(input$askdata_user_input)
      chat_append("askdata", stream)
    }, error = function(e) {
      chat_append("askdata",
                  paste("The assistant could not answer just now:", conditionMessage(e)))
    })
  })
}
