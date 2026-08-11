# Self-hosting option: build once, run anywhere (Fly.io, Railway, Render, a VPS).
# Only needed if you don't want to use shinyapps.io or Posit Connect Cloud.
#
#   docker build -t capitalbikes .
#   docker run --rm -p 3838:3838 -e MAPS_API=your_key capitalbikes
#   open http://localhost:3838

# rocker/shiny images pin an R version and ship Shiny Server preconfigured.
FROM rocker/shiny:4.4.1

# System libraries that sf / terra / elevatr / leaflet need to compile.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libudunits2-dev \
        libgdal-dev \
        libgeos-dev \
        libproj-dev \
        libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Posit Package Manager serves prebuilt Linux binaries, which turns a ~40 minute
# source compile into a couple of minutes.
RUN echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))' \
      >> /usr/local/lib/R/etc/Rprofile.site

RUN R -e "install.packages(c( \
      'shiny', 'bslib', 'markdown', 'knitr', 'ggplot2', 'plotly', \
      'dplyr', 'tidyr', 'readr', 'stringr', \
      'leaflet', 'mapsapi', 'gmapsdistance', 'elevatr' \
    ))"

WORKDIR /srv/shiny-server/capitalbikes
COPY . .

EXPOSE 3838

# Run the app directly rather than through Shiny Server, so the container has
# one process and the platform's port mapping is straightforward.
CMD ["R", "-e", "shiny::runApp('/srv/shiny-server/capitalbikes', host = '0.0.0.0', port = 3838)"]
