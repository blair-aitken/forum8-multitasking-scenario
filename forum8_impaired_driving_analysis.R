# Forum8 Multitasking Scenario: driving outcomes
# Author: Dr Blair Aitken. Additional contributor: Dr Brook Shiferaw.
# License: MIT. See LICENSE for the full terms.
# Run from the repository folder: Rscript forum8_impaired_driving_analysis.R

# 1. User settings -------------------------------------------------------------
# Edit this section to match your project. Functions below use these settings.

# Input/output folders and filename format.
input_dir <- "data/driving"
output_dir <- "output"

# Accepts STUDY_001_V1_T1.csv or STUDY001V1T1.csv.
# Captures participant ID, visit and drive.
filename_pattern <- "^.+?([0-9]{3})_?V([0-9]+)_?T([0-9]+)$"

# Task distances are in metres.
# Each window includes its start and excludes its end.
task_windows <- data.frame(
  task = c("car_following", "highway_drive", "dual_task"),
  start_m = c(3000, 14600, 27460),
  end_m = c(14400, 27460, 40500)
)
# The shared boundary at 27460 m belongs to dual_task.

# Vehicle and lane selection.
ego_type <- "uv"
target_lane <- 2
passing_lane <- 3
headway_tasks <- "car_following"

# Multiply exported Time by this value to convert it to seconds.
time_to_seconds <- 1

# Overtaking detection and recovery thresholds.
remove_overtakes <- TRUE
overtake_tasks <- "highway_drive"

# Maximum lateral speed at an approach/recovery boundary (m/s).
straight_m_s <- 0.10

# Allowed difference from median target-lane cruising speed (km/h).
speed_tolerance_kmh <- 5

# Remove shorter clean gaps between overtaking exclusions (metres).
min_gap_m <- 600

# Lateral offsets and headway are assumed to be in metres. Steering keeps its
# exported units/sign: do not take absolute values before calculating its SD.

# 2. Validate settings ---------------------------------------------------------

check_settings <- function() {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop('Install the only required package: install.packages("data.table")')
  }
  if (
    !nrow(task_windows) ||
      anyNA(task_windows) ||
      anyDuplicated(task_windows$task) ||
      any(task_windows$start_m >= task_windows$end_m)
  ) {
    stop("Check task_windows names and distance limits.")
  }
  ordered_windows <- task_windows[order(task_windows$start_m), ]
  if (
    nrow(ordered_windows) > 1 &&
      any(head(ordered_windows$end_m, -1) > tail(ordered_windows$start_m, -1))
  ) {
    stop("Task windows must not overlap.")
  }
  if (
    !is.finite(time_to_seconds) || time_to_seconds <= 0 ||
      !is.finite(straight_m_s) || straight_m_s < 0 ||
      !is.finite(speed_tolerance_kmh) || speed_tolerance_kmh < 0 ||
      !is.finite(min_gap_m) || min_gap_m < 0 ||
      target_lane == passing_lane
  ) {
    stop("Check time, lane and overtaking settings.")
  }
}

# 3. Statistical and task helpers ----------------------------------------------

# Return NA when too few finite observations are available.
safe_mean <- function(x) {
  if (!any(is.finite(x))) {
    return(NA_real_)
  }
  mean(x[is.finite(x)])
}

safe_sd <- function(x) {
  if (sum(is.finite(x)) < 2) {
    return(NA_real_)
  }
  sd(x[is.finite(x)])
}

# Find the start/end indices of consecutive TRUE values.
true_runs <- function(condition) {
  runs <- rle(condition)
  end_indices <- cumsum(runs$lengths)
  data.frame(
    start = (end_indices - runs$lengths + 1L)[runs$values],
    end = end_indices[runs$values]
  )
}

# Assign one task label to each distance sample.
assign_task <- function(distance) {
  task_labels <- rep(NA_character_, length(distance))
  for (i in seq_len(nrow(task_windows))) {
    in_window <- is.finite(distance) &
      distance >= task_windows$start_m[i] &
      distance < task_windows$end_m[i]
    task_labels[in_window] <- task_windows$task[i]
  }
  task_labels
}

# 4. Read and validate one driving file ----------------------------------------

read_drive <- function(file) {
  stem <- tools::file_path_sans_ext(basename(file))
  filename_match <- regexec(filename_pattern, stem, perl = TRUE)
  metadata <- regmatches(stem, filename_match)[[1]]
  if (length(metadata) != 4) {
    stop("Filename must match filename_pattern: ", basename(file))
  }
  drive_data <- data.table::fread(file, na.strings = c("", "NA", "NaN"))
  # Handles camelCase headers as well as spaces/underscores.
  data.table::setnames(
    drive_data,
    gsub("[^a-z0-9]", "", tolower(names(drive_data)))
  )
  if (anyDuplicated(names(drive_data))) {
    stop("Duplicate column names after normalisation: ", file)
  }
  required_columns <- c(
    "time", "type", "distancealongroad", "lanenumber",
    "speedinkmperhour", "offsetfromlanecenter", "steering"
  )
  if (remove_overtakes) {
    required_columns <- c(required_columns, "offsetfromroadcenter")
  }
  missing_columns <- setdiff(required_columns, names(drive_data))
  if (length(missing_columns)) {
    stop(
      basename(file), ": missing columns: ",
      paste(missing_columns, collapse = ", ")
    )
  }
  if (!"distancetofrontvehicle" %in% names(drive_data)) {
    warning(basename(file), ": no distanceToFrontVehicle; headway will be NA.")
    drive_data[, distancetofrontvehicle := NA_real_]
  }
  numeric_columns <- setdiff(required_columns, "type")
  numeric_columns <- union(numeric_columns, "distancetofrontvehicle")
  for (column in numeric_columns) {
    raw_values <- drive_data[[column]]
    numeric_values <- suppressWarnings(as.numeric(raw_values))
    if (any(!is.na(raw_values) & (!is.finite(numeric_values)))) {
      stop(basename(file), ": invalid numeric values in ", column)
    }
    data.table::set(drive_data, j = column, value = numeric_values)
  }
  drive_data <- drive_data[!is.na(type) & type == ego_type]
  if (!nrow(drive_data)) {
    stop("No ego-vehicle rows in ", basename(file))
  }
  drive_data[, time := time * time_to_seconds]
  if (any(!is.finite(drive_data$time)) || anyDuplicated(drive_data$time)) {
    stop(
      basename(file), ": ego Time must be finite and unique ",
      "(one continuous drive per file)."
    )
  }
  data.table::setorder(drive_data, time)
  drive_data[, task := assign_task(distancealongroad)]
  if (anyNA(drive_data$task)) {
    message(
      basename(file), ": ", sum(is.na(drive_data$task)),
      " rows outside task windows."
    )
  }
  drive_data[, `:=`(
    file = basename(file),
    id = metadata[2],
    visit = as.integer(metadata[3]),
    drive = as.integer(metadata[4])
  )]
  drive_data
}

# 5. Identify overtaking exclusions --------------------------------------------
# Return one TRUE/FALSE exclusion flag per sample within a file/task.
# Forum8 adaptation of Verster & Roth (2011), Figure 5:
# https://doi.org/10.2147/IJGM.S19639 (see README for details and limitations).

mark_overtakes <- function(task_data) {
  # Called on ONE file/task, before removing non-target-lane samples.
  n_samples <- nrow(task_data)
  excluded <- rep(FALSE, n_samples)
  if (!remove_overtakes || !task_data$task[1] %in% overtake_tasks) {
    return(excluded)
  }
  episodes <- true_runs(
    !is.na(task_data$lanenumber) & task_data$lanenumber == passing_lane
  )
  if (!nrow(episodes)) {
    return(excluded)
  }
  if (any(diff(task_data$distancealongroad) < 0, na.rm = TRUE)) {
    stop(
      task_data$file[1],
      ": distance decreases in overtaking task; check road coordinates."
    )
  }
  # offsetFromRoadCenter stays continuous across lane changes. Lane-centre
  # offset resets on a lane change, so it cannot be used for this derivative.
  lateral_speed <- c(
    NA_real_,
    diff(task_data$offsetfromroadcenter) / diff(task_data$time)
  )
  cruising_speed <- median(
    task_data$speedinkmperhour[task_data$lanenumber %in% target_lane],
    na.rm = TRUE
  )
  if (!is.finite(cruising_speed)) {
    stop(task_data$file[1], ": no target-lane cruising speed available.")
  }
  is_stable <- !is.na(task_data$lanenumber) &
    task_data$lanenumber == target_lane &
    is.finite(lateral_speed) &
    abs(lateral_speed) <= straight_m_s &
    is.finite(task_data$speedinkmperhour) &
    abs(task_data$speedinkmperhour - cruising_speed) <= speed_tolerance_kmh
  for (k in seq_len(nrow(episodes))) {
    start_index <- episodes$start[k]
    while (start_index > 1L && !is_stable[start_index]) {
      start_index <- start_index - 1L
    }
    end_index <- episodes$end[k]
    while (end_index < n_samples && !is_stable[end_index]) {
      end_index <- end_index + 1L
    }
    excluded[start_index:end_index] <- TRUE
  }
  # Fill every short internal gap, including a sole gap between two windows.
  # Gaps touching task boundaries are retained.
  gaps <- true_runs(!excluded)
  for (k in seq_len(nrow(gaps))) {
    gap_start <- gaps$start[k]
    gap_end <- gaps$end[k]
    if (gap_start > 1L && gap_end < n_samples) {
      gap_distance <- task_data$distancealongroad[gap_end + 1L] -
        task_data$distancealongroad[gap_start - 1L]
      if (is.finite(gap_distance) && gap_distance < min_gap_m) {
        excluded[gap_start:gap_end] <- TRUE
      }
    }
  }
  excluded
}

# 6. Calculate outcomes and export results -------------------------------------

main <- function() {
  check_settings()
  library(data.table)
  if (!dir.exists(input_dir)) {
    stop("Create input_dir and add Forum8 CSV exports: ", input_dir)
  }
  # Keep outputs outside the input tree so summaries are not read as raw data.
  input_path <- normalizePath(input_dir, mustWork = TRUE)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output_path <- normalizePath(output_dir, mustWork = TRUE)
  if (
    output_path == input_path ||
      startsWith(output_path, paste0(input_path, "/"))
  ) {
    stop("output_dir must be outside input_dir.")
  }
  files <- list.files(
    input_dir,
    pattern = "\\.csv$",
    full.names = TRUE,
    recursive = TRUE,
    ignore.case = TRUE
  )
  if (!length(files)) {
    stop("No CSV files found in ", input_dir)
  }
  # Validate all files before writing results.
  # Stop rather than silently skipping bad files.
  drives <- lapply(files, read_drive)
  drive_keys <- vapply(
    drives,
    function(drive_data) {
      paste(
        drive_data$id[1], drive_data$visit[1], drive_data$drive[1],
        sep = "/"
      )
    },
    character(1)
  )
  if (anyDuplicated(drive_keys)) {
    stop(
      "Multiple files have the same id/visit/drive. ",
      "Combine segments explicitly or rename drives."
    )
  }
  outcomes <- list()
  quality_checks <- list()
  exclusion_windows <- list()

  # Process each drive separately, then summarise each configured task.
  for (drive_data in drives) {
    for (task_name in task_windows$task) {
      task_data <- drive_data[!is.na(task) & task == task_name]
      if (!nrow(task_data)) {
        warning(
          drive_data$file[1], ": no samples in ", task_name,
          "; writing an NA outcome row."
        )
      }
      excluded <- if (nrow(task_data)) {
        mark_overtakes(task_data)
      } else {
        logical(0)
      }
      keep_sample <- !is.na(task_data$lanenumber) &
        task_data$lanenumber == target_lane &
        !excluded
      retained_data <- task_data[keep_sample]

      # Restrict headway to tasks with a genuine lead vehicle.
      headway <- retained_data$distancetofrontvehicle
      # Missing and negative sentinel distances are not valid following gaps.
      headway[!is.finite(headway) | headway < 0] <- NA_real_
      if (!task_name %in% headway_tasks) {
        headway[] <- NA_real_
      }
      identifiers <- drive_data[1, .(file, id, visit, drive)]
      identifiers[, task := task_name]

      # Calculate the six core driving outcomes.
      outcomes[[length(outcomes) + 1L]] <- cbind(
        identifiers,
        data.table(
          sdlp_cm = safe_sd(retained_data$offsetfromlanecenter * 100),
          sds_kmh = safe_sd(retained_data$speedinkmperhour),
          mean_speed_kmh = safe_mean(retained_data$speedinkmperhour),
          steering_variability = safe_sd(retained_data$steering),
          mean_headway_m = safe_mean(headway),
          headway_variability_m = safe_sd(headway)
          # Add further driving outcomes here using retained_data.
        )
      )

      # Record how much data contributed to each outcome.
      quality_checks[[length(quality_checks) + 1L]] <- cbind(
        identifiers,
        data.table(
          n_task = nrow(task_data),
          n_overtake_excluded = sum(excluded),
          n_retained = nrow(retained_data),
          n_other_or_missing_lane = sum(
            is.na(task_data$lanenumber) | task_data$lanenumber != target_lane
          ),
          n_lateral = sum(is.finite(retained_data$offsetfromlanecenter)),
          n_speed = sum(is.finite(retained_data$speedinkmperhour)),
          n_steering = sum(is.finite(retained_data$steering)),
          n_headway = sum(is.finite(headway))
        )
      )

      # Save final merged exclusion boundaries for manual review.
      runs <- true_runs(excluded)
      for (k in seq_len(nrow(runs))) {
        start_index <- runs$start[k]
        end_index <- runs$end[k]
        exclusion_windows[[length(exclusion_windows) + 1L]] <- cbind(
          identifiers,
          data.table(
            start_sec = task_data$time[start_index],
            end_sec = task_data$time[end_index],
            start_m = task_data$distancealongroad[start_index],
            end_m = task_data$distancealongroad[end_index],
            n_excluded = end_index - start_index + 1L,
            touches_task_start = start_index == 1L,
            touches_task_end = end_index == nrow(task_data)
          )
        )
      }
    }
  }

  # Write a consistent exclusion table, including when no events occurred.
  window_table <- if (length(exclusion_windows)) {
    rbindlist(exclusion_windows)
  } else {
    data.table(
      file = character(),
      id = character(),
      visit = integer(),
      drive = integer(),
      task = character(),
      start_sec = numeric(),
      end_sec = numeric(),
      start_m = numeric(),
      end_m = numeric(),
      n_excluded = integer(),
      touches_task_start = logical(),
      touches_task_end = logical()
    )
  }

  fwrite(
    rbindlist(outcomes),
    file.path(output_dir, "driving_outcomes.csv"),
    na = "NA"
  )
  fwrite(
    rbindlist(quality_checks),
    file.path(output_dir, "driving_quality_checks.csv"),
    na = "NA"
  )
  fwrite(
    window_table,
    file.path(output_dir, "overtaking_exclusion_windows.csv"),
    na = "NA"
  )

  # Save settings alongside results so each run can be reproduced.
  dput(
    list(
      tasks = task_windows,
      filename_pattern = filename_pattern,
      input_dir = input_path,
      ego_type = ego_type,
      target_lane = target_lane,
      passing_lane = passing_lane,
      headway_tasks = headway_tasks,
      time_to_seconds = time_to_seconds,
      remove_overtakes = remove_overtakes,
      overtake_tasks = overtake_tasks,
      straight_m_s = straight_m_s,
      speed_tolerance_kmh = speed_tolerance_kmh,
      min_gap_m = min_gap_m
    ),
    file = file.path(output_dir, "analysis_settings.R")
  )
  message(
    "Complete: ", length(files), " drives. Results saved to ", output_path
  )
}

# Run automatically from Rscript; when sourced, call main() explicitly.
if (sys.nframe() == 0L) {
  main()
}
