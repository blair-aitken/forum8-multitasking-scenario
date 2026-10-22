# Forum8 Multitasking Scenario

Use the Forum8 scenario in your own project and calculate six basic driving outcomes with one editable R script.

## Requirements

- UC-win/Road by Forum8 to run the scenario (designed using version 14; compatibility with other versions has not been verified).
- R and the `data.table` package to analyse exported data.

## Driving simulations
The UC-win/Road `forum8_impaired_driving_scenarios.rd` file contains three 8-minute driving tasks conducted on a bidirectional, four-lane highway with a lane width of 3.4 meters. The tasks are as follows:

### Highway driving task
Participants maintain a constant speed of 100 km/h in the left lane and performed four overtaking manoeuvres during a 12 km drive.

<br><img width="2880" alt="Highway_Driving_Screenshot" src="https://github.com/user-attachments/assets/fd0ba366-24cf-45eb-a90b-e86126c0c7b7"/><br>


### Car-following task
The task begins with a vehicle materialising 50 meters ahead of the participant's vehicle. Participants are instructed to follow this vehicle, maintaining a safe and consistent distance (headway) from it.

<br><img width="2880" alt="Car_Following_Screenshot" src="https://github.com/user-attachments/assets/d549c705-ac88-4ade-b0bc-e960ae545dec"><br>

The lead vehicle varied its speed in a sinusoidal pattern every 400 meters, fluctuating between 60 and 90 km/h, with single speed changes no greater than ± 10 km/h. Consequently, participants are required to adjust their speed by decelerating to avoid collisions and accelerating to keep up with the lead vehicle.

### Dual task
In this task, participants are presented with letters from A to F enclosed within a green hexagon on screens positioned at the left and right of their peripheral vision.

<br><img width="2880" alt="Dual_Task_Screenshot" src="https://github.com/user-attachments/assets/a0f412cf-04a7-403a-a25f-b335283380a7"><br>

When a letter appears, participants are required to respond quickly by pressing the corresponding button on their dashboard, followed by immediately returning both hands to the steering wheel. Participants completed a total of 50 trials in the dual task. Each letter appeared for one second, with an approximate interval of 10 seconds between each letter. Participants were instructed to maintain a constant speed of 100 km/h in the left lane while simultaneously performing the task.

## Driving outcomes

`forum8_impaired_driving_analysis.R` produces one row per participant, visit, drive and task, with these six outcomes:

| Column | Definition | Units |
| --- | --- | --- |
| `sdlp_cm` | Sample SD of signed lateral position (`offsetFromLaneCenter` × 100) | cm |
| `sds_kmh` | Sample SD of speed | km/h |
| `mean_speed_kmh` | Mean speed | km/h |
| `steering_variability` | Sample SD of signed steering | Exported steering units |
| `mean_headway_m` | Mean distance to the vehicle ahead during car-following | m |
| `headway_variability_m` | Sample SD of that distance during car-following | m |

These are calculated from ego-vehicle (`type = uv`) samples in the target lane (lane 2), after overtaking exclusions. SDLP and steering variability use signed values, rather than their absolute magnitudes.

Headway here means **distance headway**, not time headway. It is reported only for `car_following`; highway and dual-task values are `NA`. Negative or missing distances are excluded; check whether your exporter uses other sentinel values for an absent lead vehicle. Means need one valid sample; SDs need two. Missing outcomes remain `NA`.

Other driving outcomes can be calculated from the exported signals. Add them in the clearly marked summary section once their definitions and required channels have been checked. Lane departures, response times and secondary-task accuracy are not calculated by this script.

## Run the scenario and analyse data

1. Download or clone this repository. The `.rd` scenario uses Git LFS; Git users should install Git LFS and run `git lfs pull` to retrieve it.
2. Open `forum8_impaired_driving_scenarios.rd` in UC-win/Road and choose the task/version in the scenario selector.
3. Export driving data as CSV. Use one continuous recording per file, named `STUDY_001_V1_T1.csv` (study, participant, visit, drive). Compact names such as `MEDICO001V1T1.csv` also work. Participant IDs remain zero-padded strings. Separate task recordings need distinct drive numbers, or a customised filename parser.
4. Put raw CSVs in `data/driving/`. Subfolders are supported. Keep only raw driving exports in this folder.
5. Open the repository folder as your R working directory. Install the dependency once:

```r
install.packages("data.table")
```

6. Edit the settings at the top of `forum8_impaired_driving_analysis.R`, then run:

```r
source("forum8_impaired_driving_analysis.R")
main()
```

Alternatively, from a terminal in the repository folder:

```sh
Rscript forum8_impaired_driving_analysis.R
```

The script checks filenames, required columns, numeric values, unique ego-vehicle times and duplicate participant/visit/drive identifiers before exporting results.

### Required CSV columns

Headers are case-insensitive; spaces and underscores are ignored.

- `time`: numeric elapsed simulation time, in seconds by default. Change `time_to_seconds` for other units. Times must be unique for ego-vehicle samples within a file.
- `type`, `laneNumber`, `distanceAlongRoad`.
- `speedInKmPerHour`, `steering`, `offsetFromLaneCenter`.
- `offsetFromRoadCenter`: required when overtaking removal is enabled; lateral road position must be continuous across lane changes.
- `distanceToFrontVehicle`: optional; absent values produce missing headway outcomes and a warning.

Lateral positions, road distance and following distance are assumed to be exported in metres. Additional export columns are allowed. The script does not rely on a fixed sampling rate: lateral speed is calculated from consecutive recorded times.

### Editable settings

The top of the script contains the input/output folders, filename pattern, task distances, ego-vehicle type, lane numbers and overtaking settings. Defaults follow the supplied updated driving pipeline:

| Task | Start (m, inclusive) | End (m, exclusive) |
| --- | ---: | ---: |
| Car-following | 3000 | 14400 |
| Highway driving | 14600 | 27460 |
| Dual task | 27460 | 40500 |

Unassigned samples are reported and omitted. Every file receives a row for each configured task; tasks without samples have missing outcomes and zero counts. Remove unused tasks from `task_windows` if analysing separate task recordings.

## Overtaking removal

Intentional lane changes can inflate estimates of lane-keeping variability. The editing rationale follows Verster and Roth (2011), particularly Figure 5: remove overtaking from its approach until normal lane and speed are restored, and remove intervening stretches shorter than 600 m.

This script implements an **automated Forum8 adaptation**, rather than an exact reproduction of the on-road procedure:

1. Within each highway task, detect every continuous run in the passing lane (lane 3).
2. Work backwards to the last target-lane sample with low lateral motion and speed close to cruising speed, capturing the approach.
3. Exclude through the first sample back in lane 2 with low lateral motion and recovered speed. If recovery is not observed, exclude through the end of the task.
4. Merge exclusions and remove clean gaps of less than 600 m between them. Gaps at task boundaries are retained.

Cruising speed is the median recorded speed in lane 2 for that file/task. The lateral-speed threshold (0.10 m/s) and speed tolerance (±5 km/h) are editable implementation choices, not thresholds prescribed by the paper. Boundaries use individual samples; there is no minimum sustained recovery period. Missing lateral/speed values cannot establish recovery.

The same retained samples are used for all six summaries. Other lanes are removed even outside overtaking windows. No indicator filter or fixed overtaking-distance cut-outs are applied. Detection is based on passing-lane occupancy, so an unintended excursion into lane 3 can also be excluded, while an attempted overtake that never reaches lane 3 can be missed. Review the exported exclusion windows against raw traces, especially windows touching a task boundary, before using results. This does not implement the paper's full editing procedure for crashes, traffic jams or signal loss.

**Reference:** Verster, J. C., & Roth, T. (2011). Standard operation procedures for conducting the on-the-road driving test, and measurement of the standard deviation of lateral position (SDLP). *International Journal of General Medicine, 4*, 359–371. [doi:10.2147/IJGM.S19639](https://doi.org/10.2147/IJGM.S19639).

## Outputs

Results are written to `output/`, separately from raw data:

- `driving_outcomes.csv`: identifiers and the six outcomes.
- `driving_quality_checks.csv`: task/retained/excluded sample counts and valid counts for each signal. Overtaking and non-target-lane counts overlap and should not be added together. Inspect these counts before interpreting summaries; two samples are mathematically sufficient for an SD but do not establish adequate task coverage.
- `overtaking_exclusion_windows.csv`: final merged windows, including removed short gaps, with time/distance boundaries and task-boundary flags. Contains headers even when no overtakes occur.
- `analysis_settings.R`: settings used for the run.

Re-running replaces these outputs. Raw files are unchanged. Use a new output folder to keep separate runs.

## Code style

The R code follows the [tidyverse style guide](https://style.tidyverse.org/),
with two-space indentation, descriptive `snake_case` names, explicit braces,
and lines limited to 80 characters. Settings are grouped at the top of the
script; numbered sections describe each processing stage.

For optional development checks, use `styler::style_file()` and `lintr::lint()`.
These packages are not required to run the analysis. The `.lintr` configuration
excludes object-usage checks because `data.table` resolves column names at
runtime; all other default checks remain enabled.

## Attribution and reuse

Analysis script: Dr Blair Aitken, with additional contribution from Dr Brook Shiferaw. The R code is available under the [MIT License](LICENSE), which permits use, modification and redistribution while retaining the copyright and licence notice. Forum8 software requires its own licence.

When using this project in research, please cite [this repository](https://github.com/blair-aitken/forum8-multitasking-scenario) and Verster and Roth (2011) when describing the overtaking-editing rationale. Academic citation is requested separately from the MIT licence terms.

## Contact

For questions about this scenario or script, contact baitken@swin.edu.au.
