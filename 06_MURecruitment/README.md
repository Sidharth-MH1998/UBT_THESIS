# Motor-unit recruitment recording

## Plot a saved trial

Run `PlotMURecruitmentResults.m` and select a MAT file using the file dialog.
It plots all three force channels with the target above and the MU raster
below. The selected force channel is emphasized, the time axes are linked
for zooming, and demo recordings are labelled SIMULATED. Navigate to
`demo_recordings` in the dialog to inspect a demo trial. Force timestamps and
EMG sample times retain their original independent clock conventions.
Use the plot's **Sort MUs by increasing recruitment threshold (RT)** checkbox
to place the lowest threshold at the bottom; uncheck to restore original order.
Each MU label includes `(RT 12)`, for example, in percent calibrated force
(rounded for display; sorting uses the full value). RT is force at that MU's
first recorded discharge, using the saved selected-channel `signal.path`.
This is one estimate across the whole trial, not a per-repetition or sustained
recruitment estimate; a unit already firing at recording start has an onset
that predates the recording. Missing thresholds are labelled RT N/A and sort
last. Sorting changes only the display; saved trial data is unchanged.

## Test without hardware

Run `DemoMURecruitment.m`. No devices or calibration files are needed.
It opens the same recorder with a SIMULATION title and participant `DEMO`.
Press **Track Record** to see synthetic force follow the trapezoid and motor
units recruit as force increases. **Record** tests manual trial saving.
Demo files go to `demo_recordings`, with `signal.simulated` and
`recruitment.simulated` set to true. Hardware recordings set these to false.
This tests the UI/task/save path; synthetic spikes are generated directly,
so it does not validate the decomposition algorithm or hardware drivers.

Run `StartMURecruitment.m` in MATLAB. Set the grid count, physical inputs,
Arduino port, grid names and muscles in that launcher first. Select a
decomposed/edited MUedit calibration matching the connected grids, then the
force calibration. Canceling the force dialog uses the configured defaults.

The interface reuses `setupRecordingFigure`: force above, live multigrid
motor-unit raster below, and the existing recorder controls on the right.
The decoder, calibration preparation, hardware drivers and MUedit signal
builder are reused from the existing folders; those files are not modified.

1. Zero the force while unloaded and choose force direction.
2. Enter participant, session, trial, force channel and target percentage.
3. Choose **Trapezium** or **Triangular** from the Trace dropdown.
   For **Track Record**, set wait, slope and target. Trapezium also uses the
   plateau duration: rest, ramp up, hold, ramp down, rest. Triangular ramps
   from zero to the target and back without a hold; Plateau is disabled and
   ignored. Each ramp takes Slope seconds. Recording saves automatically after
   `2*wait + 2*slope + plateau` seconds for Trapezium, or
   `2*wait + 2*slope` for Triangular. Pressing Track Record again ends it early.
   Set **Repetitions** to a positive integer (default 3) to repeat the full
   task, including its initial and final waits, N times. All repetitions are
   saved together in one trial; total duration is N times the single-task
   duration. The setting is captured at trial start and also works in demo
   mode. Manual Record is still stopped manually.
   The selected shape and count are stored in `recruitment.trial.traceType`
   and `recruitment.trial.repetitions`; `cycleDuration` and `duration` store
   single-task and total planned durations in seconds.
4. **Record** starts/stops a manual trial. Recording modes are mutually exclusive.
5. **Close** or the configured maximum duration saves an active partial trial.
   Closing the figure uses the same stop path. Trial increments after saving.

Files go into `06_MURecruitment/recordings` by default:
`S<participant>_ss<session>_dig<channel>_f<target>_t<trial>.mat`.
Existing files receive a `_repeatN` suffix rather than being overwritten.

Each MAT file contains:

- `signal`: MUedit-compatible EMG, sampling rate, grid/muscle metadata,
  all three native-rate force channels, selected force path resampled to EMG
  length, target trace, force receipt timestamps, Arduino timestamps and
  force calibration settings.
- `recruitment`: pulse trains, samples-by-MU logical raster, trial-relative
  discharge sample indices (one-based), grid/MU mapping, frozen trial
  settings, configuration and session start positions.

Zero and force-direction controls are locked during a trial. Target task and
participant settings are captured at trial start. The displayed target and
force use session receipt time; raster timing uses the EMG sample clock.
Arduino and Novecento have independent clocks, so this does not provide
hardware synchronization. `signal.path` uses the existing recorder's
length-based force interpolation. Task completion is serviced between EMG
blocks and can include up to one extra processing block plus hardware latency.
An early tracking stop saves the available trial; `interrupted` flags a
session-close/duration-limit stop.

Acquisition buffers are retained for the session, bounded by
`cfg.forceMaxDurationSec`; large grid counts and long sessions require RAM.
Unexpected hardware or save errors propagate to MATLAB and release device
connections; automatic recovery or partial-data saving on such errors is
not implemented.

Runtime validation requires MATLAB with working MathWorks services and the
Arduino/Novecento hardware. MATLAB startup in the development environment
failed with MathWorks service error 5202, so live acquisition is unverified.
