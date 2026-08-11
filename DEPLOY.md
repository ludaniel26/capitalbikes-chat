# Deploying capitalbikes

This directory is a slimmed, deploy-ready copy of
`WL-Biol185-ShinyProjects/capitalbikes` — 448 KB instead of 1.8 GB, with the
startup problems fixed.

---

## What was wrong with the original repo

**1. The repo is 1.8 GB, but the app reads 448 KB of it.**

`ui.R`, `server.R` and `stationSelector.r` only ever open eight things:

| File | Read by |
|---|---|
| `bike_numbers.csv` | `ui.R` — populates the station dropdowns |
| `total_bikes.csv` | `server.R`, `stationSelector.r` — map markers |
| `mergedweatherdata.csv` | `server.R` — all three Weather Trends plots |
| `2023-station-frequency/*.rds` (12) | `server.R` — Station Frequency tab |
| `www/CapitalBikeshareStationDockedBikes.jpg` | `ui.R` — About tab image |

Everything else — the twelve ~50 MB monthly trip CSVs, `monthly-data/`,
`monthly-time-dif-rds/`, `usage_frequency.csv`, the `.Rmd` notebooks and their
knitted HTML — is the data-cleaning work that *produced* those small files. It
was useful for the course, but the app never touches it, and shipping it will
blow past the bundle limits on every hosting platform.

**2. The committed `manifest.json` is broken.** It lists exactly two files,
`server.R` and `ui.R` — no CSVs, no RDS files, no `www/`. Any deploy driven by
it starts up and dies immediately on
`read.csv("bike_numbers.csv"): cannot open file`. Delete it and regenerate.

**3. `server.R` uses leaflet and mapsapi without attaching them.** It calls
`leaflet()`, `addProviderTiles()`, `leafletProxy()`, `makeIcon()` and
`mp_directions()`, but only `ui.R` has `library(leaflet)` / `library(mapsapi)`.
This works by accident — Shiny sources both files into the same environment —
and breaks the moment anyone reorganises the files. Now fixed in `global.R`.

**4. A missing Google Maps key crashed the Bike Router.** `Sys.getenv("MAPS_API")`
returns `""` when unset, the Directions API rejects the call, and the unhandled
error killed the session. It now shows a notification and leaves the rest of
the app running.

**5. `library(tidyverse)` pulled in ~90 packages.** The app uses `dplyr`,
`ggplot2` and a little `tidyr`. The meta-package was the single biggest driver
of deploy time. Replaced with targeted imports.

---

## Step 0 — Run it locally first

Never debug a deploy you haven't seen work locally.

```r
install.packages(c(
  "shiny", "bslib", "markdown", "knitr", "ggplot2", "plotly",
  "dplyr", "tidyr", "readr", "stringr",
  "leaflet", "mapsapi", "gmapsdistance", "elevatr"
))

setwd("path/to/capitalbikes-deploy")
shiny::runApp()
```

Four of the five tabs should work with no key at all. If they do, the app is
fine and anything that fails later is a hosting problem.

**Watch for:** `elevatr` depends on `sf`/`terra`, which need system geospatial
libraries (GDAL, GEOS, PROJ). On macOS: `brew install gdal geos proj udunits`.
On Ubuntu: `sudo apt install libgdal-dev libgeos-dev libproj-dev libudunits2-dev`.
This is the most common local install failure.

### The Google Maps key

Only the Bike Router tab needs it. Get one from the Google Cloud Console and
enable **both** the **Directions API** and the **Distance Matrix API** on a
project with billing enabled — the free monthly credit covers a project like
this comfortably, but both APIs must be switched on individually or you'll get
`REQUEST_DENIED`.

Then `cp .Renviron.example .Renviron`, paste your key in, and restart R.

Before deploying, restrict the key in the Cloud Console to the two APIs above
and set a low daily quota cap. A key on a public site is a key that gets
scraped.

---

## Option A — shinyapps.io (easiest, free tier)

Best if you want a URL today and don't care about it being tied to your laptop.

<cite index="1-1">The free plan allows up to 25 active hours per month; if you exceed that, visitors see a notice that the application is unavailable</cite>, and <cite index="3-1">it's capped at 5 applications</cite>. <cite index="4-1">An app sleeps after an idle period (15 minutes by default) which stops active hours from accruing</cite> — worth shortening in the dashboard if the link is going somewhere public.

```r
install.packages("rsconnect")

# Token and secret come from shinyapps.io -> Account -> Tokens -> Show
rsconnect::setAccountInfo(
  name   = "your-account",
  token  = "XXXX",
  secret = "XXXX"
)

setwd("path/to/capitalbikes-deploy")
rsconnect::deployApp(appName = "capitalbikes")
```

**The key on shinyapps.io.** There's no secrets UI, so the working approach is
to include `.Renviron` in the bundle. It's gitignored, so it stays out of
GitHub, but it does ship to Posit's servers:

```r
rsconnect::deployApp(
  appName  = "capitalbikes",
  appFiles = c(
    "global.R", "ui.R", "server.R", "stationSelector.r",
    "bike_numbers.csv", "total_bikes.csv", "mergedweatherdata.csv",
    "2023-station-frequency", "www", ".Renviron"
  )
)
```

If a deploy fails, `rsconnect::showLogs()` gives you the R-level error rather
than the generic "an error has occurred" page.

---

## Option B — Posit Connect Cloud (best fit for a GitHub project)

This is the better long-term answer for your case, for two reasons: it deploys
straight from the repo and redeploys on push, and it has real secret
environment variable management — so `MAPS_API` lives in a settings panel
instead of inside your app bundle.

<cite index="11-1">All you need to deploy a Shiny for R app to Connect Cloud is a public GitHub repository with a primary file and a dependency file named manifest.json.</cite>

1. Push this directory to a **new** public repo (don't reuse the 1.8 GB one —
   the history alone will make cloning miserable).

2. Regenerate the manifest from inside the app directory, replacing the broken
   two-file one:

   ```r
   setwd("path/to/capitalbikes-deploy")
   rsconnect::writeManifest()
   ```

   <cite index="19-1">Call `writeManifest` from within the directory containing the content you want to deploy, not from the project root.</cite> Then confirm it worked — this should print ~20 files, not 2:

   ```r
   length(jsonlite::fromJSON("manifest.json")$files)
   ```

3. Commit `manifest.json` and push.

4. Sign in to Connect Cloud, click Publish, pick the repo and branch, and set
   `MAPS_API` as a secret environment variable during setup.

---

## Option C — Docker (full control, no platform limits)

Use the included `Dockerfile` if you want no active-hour cap, or you're hosting
on Fly.io / Railway / Render / your own VPS.

```sh
docker build -t capitalbikes .
docker run --rm -p 3838:3838 -e MAPS_API=your_key capitalbikes
```

The first build takes a while (the geospatial stack is large), but it's the
only option here that pins the exact R and system-library versions, so it won't
quietly break when CRAN moves on.

---

## A note on why the old manifest pinned R 4.1.2

The committed manifest targets R 4.1.2 with shiny 1.7.1, leaflet 2.1.1 and
tidyverse 1.3.1 — a 2022-era snapshot. Don't try to reproduce that environment;
those binaries are hard to obtain now. Regenerate the manifest against current
packages instead. The app code is plain enough that nothing in it depends on
old package behaviour.

## Known rough edges (not blockers)

- `source("stationSelector.r")` runs *inside* the server function with the
  default `local = FALSE`, so it writes `stations` into the global environment
  on every new session. Harmless here since every session reads the same file,
  but it's the kind of thing that causes cross-session bugs if the app grows.
- `ui.R` and `server.R` both define a global named `stations` from *different*
  files (`bike_numbers.csv` vs `total_bikes.csv`). The UI is built first, so
  the dropdowns are correct, but the shared name is a trap.
- `noprecip <- filter(weather, is.na(Preciptype))` assumes blank cells parse as
  `NA`. If `read.csv` gives you `""` instead, that bar reads `NaN`. Check the
  precipitation plot renders four bars.
