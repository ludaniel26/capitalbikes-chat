Original Project: Analysis of 2023 Capital Bikeshare data and maps for real-world biking.
Built by Ava GianGrasso, Daniel Lu, and Hatcher Cook at Washington and Lee University.

V1: https://github.com/WL-Biol185-ShinyProjects/capitalbikes

V2(capitalbikes-chat): https://ludaniel26-capitalbikes.share.connect.posit.cloud
Upgraded UI, added turn-by-turn routing, and added an AI chat assistant function (CapRi). Deployed using Posit Connect Cloud: https://ludaniel26-capitalbikes.share.connect.posit.cloud.

In order to properly access the Google Maps API for the Bike Station Map and Bike Router, create a local environment environment variable: Sys.setenv("MAPS_API" = "ENTER YOUR API KEY HERE").
To properly access the CapRi API for the AI chat assistant, create a local environment environment variable: Sys.setenv("ANTHROPIC_API_KEY" = "ENTER YOUR API KEY HERE")
