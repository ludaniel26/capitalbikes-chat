# global.R -- sourced once at app startup, before ui.R and server.R.
# Everything here is loaded ONCE for the whole app rather than once per visitor,
# which is why the data reads live here instead of inside the server function.

library(shiny)
library(bslib)
library(markdown)
library(ggplot2)
library(plotly)
library(dplyr)
library(tidyr)
library(readr)
library(stringr)
library(leaflet)
library(mapsapi)
library(gmapsdistance)
library(elevatr)
library(ellmer)
library(shinychat)

# ---------------------------------------------------------------- credentials

# Google Maps key for the Bike Router tab.
# Local dev: put MAPS_API=your_key in a .Renviron file (already gitignored).
# Connect Cloud: set MAPS_API as a secret environment variable in the UI.
MAPS_API_KEY <- Sys.getenv("MAPS_API", unset = "")

if (!nzchar(MAPS_API_KEY)) {
  warning(
    "MAPS_API is not set. Every tab except 'Bike Router' will work normally; ",
    "route planning will show a message instead of a route.",
    call. = FALSE
  )
}


# ---------------------------------------------------------------------- data

# total_bikes.csv is a superset of bike_numbers.csv (same 778 stations, plus a
# total column), so one object serves the map, the dropdowns and the router.
stations <- read.csv("total_bikes.csv", stringsAsFactors = FALSE)

stations$dock_band <- cut(
  stations$total_bikes_available,
  breaks = c(-Inf, 5, 15, Inf),
  labels = c("Low", "Moderate", "Well stocked")
)

station_choices <- sort(stations$name)

weather_data <- read.csv("mergedweatherdata.csv", stringsAsFactors = FALSE)
weather_data$Date <- as.Date(weather_data$Date)
daily_rides <- read.csv("daily_rides.csv", stringsAsFactors = FALSE)
daily_rides$Date <- as.Date(daily_rides$Date)
weather_data <- dplyr::left_join(weather_data, daily_rides, by = "Date")

# Precipitation summary, computed once. Blank cells are treated as "no precip"
# whether read.csv gives back NA or an empty string.
.no_precip <- is.na(weather_data$Preciptype) | trimws(weather_data$Preciptype) == ""

precip_summary <- data.frame(
  preciptype = factor(
    c("No precipitation", "Rain", "Freezing rain", "Snow"),
    levels = c("No precipitation", "Rain", "Freezing rain", "Snow")
  ),
  durationavg = c(
    mean(weather_data$Duration[.no_precip], na.rm = TRUE),
    mean(weather_data$Duration[weather_data$Preciptype %in% "rain"], na.rm = TRUE),
    mean(weather_data$Duration[weather_data$Preciptype %in% c("freezingrain", "rain,freezingrain")], na.rm = TRUE),
    mean(weather_data$Duration[weather_data$Preciptype %in% c("snow", "rain,snow")], na.rm = TRUE)
  )
)

# The twelve monthly files, loaded in one pass instead of twelve copy-pasted
# blocks. Names match the month dropdown exactly.
MONTHS <- c("January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December")

station_freq <- lapply(seq_along(MONTHS), function(i) {
  readRDS(sprintf("2023-station-frequency/2023%02d_station_freq.rds", i)) %>%
    filter(start_station_name != "") %>%
    arrange(desc(n)) %>%
    slice_head(n = 10)
})
names(station_freq) <- MONTHS

busiest_overall <- station_freq[["October"]]$start_station_name[1]


# ------------------------------------------------------------- station notes

# Hand-written descriptions for 18 notable stations. Text unchanged from the
# original project.
STATION_BLURBS <- list(
    "Columbus Circle/ Union Station" = "Union Station is the busiest start station for Capital Bike users. It is also one of the busiest train stations in the United States. In Union Station, you can find an assortment of shops and food options. Nearby to Union station, you can visit the U.S. Capitol, explore the different Smithsonian museums like the National Museum of Natural History or the National Museum of American History, appriciate artwork at the National Gallery of Art, wander through the National Postal Museum, or visit the Library of Congress- all just a quick bike ride away!",
    "New Hampshire Ave & T St NW" = "This station is consistently one of the buisiest stations for Capital Bikeshare users. Close to Dupont Cirlce, this staion is also near The Phillips Collection – a world-renowned art museum with works by Picasso, Rothko, and Van Gogh. From here, the White House is also very accesible by bike.",
    "15th & P St NW" = "From this station, Logan Circle is just a few blocks away. This residential area has a beautiful public park in the very center and is surrounded by Victorian houses. It lends itself to a lazy Sunday afternoon stroll and has cafes such as The Roasted Boon Co. and Slipstream. If you're looking for a bike destination, try The Washington National Cathedral, a DC architectural landmark, which is only a 15 minute bike ride way.",
    "5th & K St NW" = "In the heart of downtown, this station is close to Penn Quarter. Here, you can visit the National Portrait Gallery, the Smithsonian American Art Museum, and the Capital One Arena to catch a Washington Wizards game or a concert. Bike 7 minutes west to reach Lafayette park.",
    "1st & M St NE" = "Union Market is closeby to this station and includes a trendy food hub with local eateries and vendors. It's also close to the H Street Corridor which has great nightlife. Pick up a bike and ride 10 minutes to the Atlas District- DC's arts and entertainment neighborhood- or head west towards the U.S. Capitol and explore the the Library of Congress.",
    "14th & V St NW" = "This station is in the historic U Street Corridor, where you can find American cultural landmarks. Visit the African American Civil War Museum and iconic jazz venues like the 9:30 Club. From here, cycle toward the National Mall and visit monuments like the Washington Monument and the U.S. Capitol.",
    "14th & R St NW" = "A short distance from the Logan Circle neighborhood, this area features excellent restaurants, local shops, and beautiful Victorian row houses. Bike down to the National Mall or head toward the Dupont Circle area, known for its shops, cafes, and welcoming community.",
    "17th & Corcoran St NW" = "In the Dupont Circle neighborhood, this station is close to The Phillips Collection – a world-renowned art museum with works by Picasso, Rothko, and Van Gogh -  and the many cafes and shops around Dupont Circle. The Smithsonian Museums and the National Gallery of Art are a short 5-10 minute ride away.",
    "8th & O St NW" = "This station is near the Shaw neighborhood, known for its African American history and revitalized community. The historic Howard Theatre and the African American Civil War Memorial are within walking distance. Bike south towards the National Mall to see the monuments, or bike to the U Street Corridor for its nightlife and drop your bike at the 14th & V St NW station.",
    "Eastern Market Metro/ Pennsylvania Ave & 8th St SE" = "Eastern Market is one of DC's oldest markets. Here, you can shop for fresh produce, local meats, and even handmade art. Nearby, you’ll find Barracks Row and the historic Capitol Hill neighborhood. Bike towards the National Mall, or head north to the U.S. Capitol and the Library of Congress.",
    "Massachusetts Ave & Dupont Circle NW" = "Around Dupont Circle, you'll find cafes, art galleries, and unique boutiques. Dupont Circle itself hosts beautuil gardens you are welcome to explore. The White House is a 7 minute bike ride away from Dupont Cirlce.",
    "Jefferson Memorial" = "The Jefferson Memorial is a neoclassical monument depicting Thomas Jefferson, a bit removed from the other monuments at the National Mall. Admire the the Tidal Basin and the Washington Monument from a distance. Bike around the Tidal Basin, or bike to the nearby Martin Luther King Jr. Memorial and Franklin Delano Roosevelt Memorial, also removed from the National Mall. The Lincoln Memorial and the National World War II Memorial are a 5 minute bike ride away.",
    "Smithsonia-National Mall/ Jefferson Dr & 12th St SW" = "From this station, go to the National Museum of American History, National Museum of Natural History, and National Air and Space Museum- all for free. Walk through the National Mall and see the Washington Monument. Just a half mile away is the Hirshhorn Museum and Sculpture Garden, a well-known art museum, which is only 3 minutes away by bike.",
    "Lincoln Memorial" = "The famous Lincoln Memorial is at this station. Enjoy the Reflecting Pool and Washington Monument, walk along the National Mall and visit other nearby monuments, like the Vietnam Veterans Memorial and the Korean War Veterans Memorial.The National World War II Memorial is a 3 minute bike ride east, and the White House and Lafayette Park are just 10 minutes north.",
    "Henry Bacon Dr & Lincoln Memorial Circle NW" = "Similar to the Lincoln Memorial station, you can explore the monument and the surrounding area. This is a great starting point for a bike ride around the Tidal Basin or along the National Mall.",
    "4th St & Madison Dr NW" = "This station is located near the National Gallery of Art. Stop by the National Archives to see the original U.S. Constitution, Bill of Rights, and Declaration of Independence! You can bike to the Smithsonian Institution or The National Gallery of Art Sculpture Garden, both 3 minutes away by bike.",
    "M St & Delaware Ave NE" = "From here, explore the Union Market district with its hip food vendors and local shops and boutiques. Ride through the beautiful Capitol Hill neighborhood and admire the historic homes. Union station is a 5 minute ride away.",
    "Adams Mill & Columbia Rd NW" = "A bit way from city center, visit the Adams Morgan neighborhood, known for its diverse cultural scene and great nightlife. 8 minutes away by bike, The National Zoo is a free and family-friendly destination with hundreds of animals and exhibits."
    
  )

# --------------------------------------------------------- matching + helpers

# Forgiving station lookup: ignores case, punctuation and word order, and
# tolerates small typos. Returns the indices of STATION_BLURBS that matched.
normalise_station <- function(x) {
  x <- tolower(x)
  x <- gsub("&", " and ", x, fixed = TRUE)
  x <- gsub("[^a-z0-9 ]", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

match_station <- function(query) {
  typed <- normalise_station(query)
  if (!nzchar(typed)) return(integer(0))

  pool <- normalise_station(names(STATION_BLURBS))

  hit <- which(pool == typed)
  if (length(hit)) return(hit)

  hit <- grep(typed, pool, fixed = TRUE)
  if (length(hit)) return(hit)

  words <- Filter(nzchar, strsplit(typed, " ")[[1]])
  if (length(words)) {
    hit <- which(vapply(
      pool,
      function(nm) all(vapply(words, function(w) grepl(w, nm, fixed = TRUE), logical(1))),
      logical(1)
    ))
    if (length(hit)) return(hit)
  }

  dists <- utils::adist(typed, pool, partial = TRUE)[1, ]
  if (min(dists) <= 3) return(which(dists == min(dists)))

  integer(0)
}


# ------------------------------------------------------------- design tokens

INK   <- "#0E1620"  # deep navy, headers and nav
SLATE <- "#5A6B7B"  # secondary text
RED   <- "#D2232A"  # Capital Bikeshare red, the one hot accent
TEAL  <- "#10707E"  # Potomac, data secondary
GOLD  <- "#C8A44D"  # monument gold, tertiary
GREEN <- "#1E7A4A"  # well-stocked docks, map only
PAPER <- "#EDF0F3"  # cool page background


# A single ggplot theme so every chart in the app reads as one family.
theme_capital <- function() {
  theme_minimal(base_size = 13) +
    theme(
      text            = element_text(colour = INK),
      plot.title      = element_blank(),   # card headers carry the title instead
      axis.title      = element_text(colour = SLATE, size = 11),
      axis.text       = element_text(colour = SLATE, size = 10),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = "#DCE2E8", linewidth = 0.4),
      plot.margin     = margin(8, 8, 8, 8)
    )
}


# ------------------------------------------------------------- UI components

# A stat tile. Deliberately hand-built rather than bslib::value_box so the app
# doesn't depend on a specific bslib version.
stat_tile <- function(label, value, sub = NULL, accent = c("ink", "red", "teal", "gold", "green")) {
  accent <- match.arg(accent)
  div(
    class = paste0("tile tile--", accent),
    div(class = "tile__label", label),
    div(class = "tile__value", value),
    if (!is.null(sub)) div(class = "tile__sub", sub)
  )
}

# The signature device: a transit route line with stations on it. Used as the
# rule under every page heading, so the divider says "route" rather than "line".
route_line <- function() {
  div(
    class = "routeline",
    span(class = "routeline__dot"),
    span(class = "routeline__bar"),
    span(class = "routeline__dot routeline__dot--mid"),
    span(class = "routeline__bar"),
    span(class = "routeline__dot")
  )
}

page_head <- function(eyebrow, title, lede) {
  div(
    class = "pagehead",
    div(class = "pagehead__eyebrow", eyebrow),
    h2(class = "pagehead__title", title),
    route_line(),
    p(class = "pagehead__lede", lede)
  )
}

ANTHROPIC_KEY <- Sys.getenv("ANTHROPIC_API_KEY", unset = "")

# Everything the assistant is allowed to know, computed once from the real data.
build_fact_sheet <- function() {
  w <- weather_data
  has_rides <- "rides" %in% names(w)
  
  monthly <- w %>%
    mutate(month = format(Date, "%B")) %>%
    group_by(month) %>%
    summarise(
      days     = n(),
      avg_dur  = round(mean(Duration, na.rm = TRUE), 1),
      avg_temp = round(mean(Tempavg,  na.rm = TRUE), 1),
      rides    = if (has_rides) sum(rides, na.rm = TRUE) else NA_real_,
      .groups  = "drop"
    )
  
  precip <- w %>%
    mutate(cond = ifelse(is.na(Preciptype) | trimws(Preciptype) == "",
                         "dry", Preciptype)) %>%
    group_by(cond) %>%
    summarise(
      days    = n(),
      avg_dur = round(mean(Duration, na.rm = TRUE), 1),
      rides   = if (has_rides) round(mean(rides, na.rm = TRUE)) else NA_real_,
      .groups = "drop"
    )
  
  top_stations <- sapply(MONTHS, function(m) {
    d <- station_freq[[m]]
    paste0(m, ": ", d$start_station_name[1], " (",
           format(d$n[1], big.mark = ","), " departures)")
  })
  
  paste(
    "DATASET: Capital Bikeshare, Washington DC, calendar year 2023.",
    "Each weather row is ONE DAY (365 rows). 'Duration' is the AVERAGE ride",
    "length in minutes for that day, not a total.",
    "",
    "YEAR OVERALL:",
    sprintf("- Average ride: %.1f minutes", mean(w$Duration, na.rm = TRUE)),
    sprintf("- Longest average day: %.1f min on %s",
            max(w$Duration, na.rm = TRUE),
            format(w$Date[which.max(w$Duration)], "%B %d")),
    sprintf("- Shortest average day: %.1f min on %s",
            min(w$Duration, na.rm = TRUE),
            format(w$Date[which.min(w$Duration)], "%B %d")),
    sprintf("- Correlation, temperature vs ride length: %.2f",
            cor(w$Tempavg, w$Duration, use = "complete.obs")),
    if (has_rides) sprintf("- Total rides in 2023: %s",
                           format(sum(w$rides, na.rm = TRUE), big.mark = ",")),
    if (has_rides) sprintf("- Fewest rides: %s on %s",
                           format(min(w$rides, na.rm = TRUE), big.mark = ","),
                           format(w$Date[which.min(w$rides)], "%B %d")),
    "",
    "BY MONTH:",
    paste(apply(monthly, 1, function(r) paste0(
      "- ", r[["month"]], ": avg ride ", r[["avg_dur"]], " min, avg temp ",
      r[["avg_temp"]], "F",
      if (has_rides) paste0(", ", format(as.numeric(r[["rides"]]), big.mark = ","), " rides") else ""
    )), collapse = "\n"),
    "",
    "BY PRECIPITATION:",
    paste(apply(precip, 1, function(r) paste0(
      "- ", r[["cond"]], ": ", r[["days"]], " days, avg ride ", r[["avg_dur"]], " min",
      if (has_rides) paste0(", avg ", r[["rides"]], " rides/day") else ""
    )), collapse = "\n"),
    "",
    "BUSIEST START STATION EACH MONTH:",
    paste("-", top_stations, collapse = "\n"),
    "",
    sprintf("STATIONS: %d docks. Bike counts are a live SNAPSHOT, not 2023 history.",
            nrow(stations)),
    sep = "\n"
  )
}

FACT_SHEET <- build_fact_sheet()

ASSISTANT_PROMPT <- paste(
  "You answer questions about a Capital Bikeshare dataset for a public website.",
  "",
  "RULES:",
  "1. Use ONLY the figures in the DATA below. Never estimate, extrapolate or",
  "   recall numbers from your own training.",
  "2. If the data cannot answer the question, say so plainly and name what is",
  "   missing. Do not guess.",
  "3. Duration is average ride LENGTH per day. Do not describe it as a count",
  "   of rides.",
  "4. Bike availability is a current snapshot, not 2023 history.",
  "5. Two or three sentences. Cite the actual numbers. No preamble.",
  "6. Correlation is not causation; describe patterns, not causes.",
  "",
  "DATA:",
  FACT_SHEET,
  sep = "\n"
)