# Synthetic checks only; run from repository root:
# Rscript tests/check_driving_analysis.R
source("forum8_impaired_driving_analysis.R")
check_settings()
library(data.table)
stopifnot(identical(
  assign_task(c(14400, 14600, 27460, 40500)),
  c(NA_character_, "highway_drive", "dual_task", NA_character_)
))
stopifnot(
  is.na(safe_mean(numeric())), is.na(safe_sd(1)),
  isTRUE(all.equal(safe_sd(c(-1, 1)), sqrt(2)))
)
x <- data.table(
  file = "TEST_001_V1_T1.csv", task = "highway_drive", time = 1:100,
  distancealongroad = 15000 + (0:99) * 25, lanenumber = 2,
  speedinkmperhour = 100, offsetfromroadcenter = 9
)
x[20:25, `:=`(lanenumber = 3, offsetfromroadcenter = 12)]
x[40:45, `:=`(lanenumber = 3, offsetfromroadcenter = 12)]
# The single internal gap must be removed, but task-boundary gaps retained.
stopifnot(identical(which(mark_overtakes(x)), 19:47))
# Long gaps remain available for analysis.
min_gap_m <- 0
stopifnot(identical(which(mark_overtakes(x)), c(19:27, 39:47)))
min_gap_m <- 600
# Missing recovery speed must not crash a while-loop or establish recovery.
x[46:100, speedinkmperhour := NA_real_]
stopifnot(tail(which(mark_overtakes(x)), 1) == 100L)
# No overtake -> no exclusions.
x[, lanenumber := 2]
stopifnot(!any(mark_overtakes(x)))

# End-to-end: signed SDs, headway scope, missing tasks, empty-window CSV,
# repeat runs, and duplicate identity rejection.
root <- tempfile("forum8-check-")
dir.create(root)
on.exit_cleanup <- function() unlink(root, recursive = TRUE)
input_dir <- file.path(root, "data")
output_dir <- file.path(root, "output")
dir.create(input_dir)
f <- data.table(
  Time = 0:5, Type = "uv", LaneNumber = 2,
  DistanceAlongRoad = c(3000, 3100, 14600, 14700, 27460, 27500),
  SpeedInKmPerHour = c(60, 80, 100, 100, 100, 100),
  OffsetFromLaneCenter = c(-0.1, 0.1, -0.2, 0.2, 0, 0),
  Steering = c(-1, 1, -2, 2, 0, 0), OffsetFromRoadCenter = 9,
  DistanceToFrontVehicle = c(40, 60, 2000, 3000, NA, NA)
)
fwrite(f, file.path(input_dir, "TEST_001_V1_T1.csv"))
main()
a <- fread(file.path(output_dir, "driving_outcomes.csv"), colClasses = c(id = "character"))
stopifnot(
  nrow(a) == 3, a$id[1] == "001",
  isTRUE(all.equal(a[task == "car_following", sdlp_cm], sd(c(-10, 10)))),
  isTRUE(all.equal(a[task == "car_following", steering_variability], sd(c(-1, 1)))),
  a[task == "car_following", mean_headway_m] == 50,
  all(is.na(a[task != "car_following", mean_headway_m])),
  nrow(fread(file.path(output_dir, "overtaking_exclusion_windows.csv"))) == 0
)
main() # existing outputs are not ingested
fwrite(f[1:2], file.path(input_dir, "TEST_001_V1_T1.csv"))
suppressWarnings(main())
a <- fread(file.path(output_dir, "driving_outcomes.csv"))
stopifnot(nrow(a) == 3, all(is.na(a[task != "car_following", sdlp_cm])))
fwrite(f, file.path(input_dir, "OTHER001V1T1.csv"))
stopifnot(inherits(try(main(), silent = TRUE), "try-error"))
unlink(file.path(input_dir, "OTHER001V1T1.csv"))
f$Time[2] <- f$Time[1]
fwrite(f, file.path(input_dir, "TEST_001_V1_T1.csv"))
stopifnot(inherits(try(main(), silent = TRUE), "try-error"))
on.exit_cleanup()
message("All synthetic checks passed.")
