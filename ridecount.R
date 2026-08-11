library(dplyr)

data_dir <- "~/Downloads/Capital Bikes Data"   # <-- edit to your actual path

files <- list.files(data_dir, pattern = "\\.rds$", full.names = TRUE)
cat("Found", length(files), "files\n\n")

# Locate the ride start-time column, whatever it happens to be called.
find_start_col <- function(df) {
  nm <- names(df)
  cand <- nm[grepl("start", nm, ignore.case = TRUE) &
               grepl("at$|time|date", nm, ignore.case = TRUE)]
  if (length(cand)) return(cand[1])
  is_time <- vapply(df, function(x) inherits(x, c("POSIXct", "POSIXt", "Date")), logical(1))
  if (any(is_time)) return(nm[which(is_time)[1]])
  NA_character_
}

daily_rides <- lapply(files, function(f) {
  d   <- readRDS(f)
  col <- find_start_col(d)
  if (is.na(col)) stop("No start-time column found in ", basename(f),
                       ". Columns are: ", paste(names(d), collapse = ", "))
  
  dates <- as.Date(d[[col]])
  out <- as.data.frame(table(Date = dates), stringsAsFactors = FALSE)
  names(out) <- c("Date", "rides")
  out$Date <- as.Date(out$Date)
  
  cat(sprintf("%-20s col='%s'  %s rows  %s days\n",
              basename(f), col, format(nrow(d), big.mark = ","), nrow(out)))
  out
}) %>%
  bind_rows() %>%
  group_by(Date) %>%
  summarise(rides = sum(rides), .groups = "drop") %>%
  arrange(Date)