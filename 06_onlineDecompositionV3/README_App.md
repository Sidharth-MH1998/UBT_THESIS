# Online decomposition app

Run `StartOnlineApp` from this folder. The workspace variable `onlineApp` holds
the app. The existing script launcher and standalone demo remain available.

## Sources

- **Simulation** generates three synthetic MUs per configured grid and three
  synthetic force channels. It requires no files or hardware. This exercises
  the interface and recording workflow, rather than EMG decoding accuracy.
- **Replay calibration** processes the imported recording's EMG window by window
  through the actual per-grid I-Spin decoders. Stored `signal.recordedForce`
  is replayed at `signal.fs_force`, or the configured Force sampling rate
  (default 50 Hz) when that metadata is absent. These already calibrated values
  are not recalibrated, reversed, zeroed or smoothed again. Force timestamps are
  reconstructed from sample order, starting at zero; original device timestamps
  are unavailable. Force stops at its last stored sample instead of being stretched
  to match EMG. If the file has no recorded force, force remains simulated and
  the status message identifies it. Replay ends
  at the last complete EMG window; a shorter final window is not processed.
- **Hardware** uses live Novecento EMG and Arduino force. Import an edited
  decomposition first, choose the Arduino port and check the grid/channel
  mapping. Every input's sampling frequency must match the offline recording.
  The reused DataRecording connector uses Ethernet at `169.254.1.10:23456`.

The defaults assume one 64-electrode grid per 70-channel probe. Physical input
order must match calibration grid order. Stream rows `1:64`, `71:134`, etc.
exclude each probe's six auxiliary channels. Changing the number of grids
restores that standard mapping; the lists can then be adjusted manually.

## Recording a trial

1. Select the source. For replay/hardware, import the edited decomposition.
2. Import force calibration, or configure the default factors, zero values,
   and reversals. A cancelled calibration picker uses the defaults.
3. Set participant, session, trial, output folder, and acquisition settings.
4. Press **Start acquisition** to prepare the decoders and start the preview.
5. With the force unloaded, use **Zero force** if needed. Zeroing is disabled
   during recording so a trial keeps a consistent calibration.
6. Press **Start recording** to begin retaining a segment.
7. Press **Stop recording** to finish it. The preview continues, and the trial
   number advances. Auto-save writes a unique MAT file when enabled.
8. Press **Stop acquisition** to finish an active recording and release devices.

An unrecorded preview is not retained. Each explicit recording starts its own
sample indices and time vector at zero; preview gaps between trials are excluded.
The configured force capacity also ends a recording, leaving the preview running.
The session-duration limit ends acquisition. Acquisition settings and calibration
imports are locked during acquisition. Participant/trial/output settings and the
quadrant window's settings are locked during recording.

## Displays

In **Display**, enable **Show MVC target line** and set **Force target (% MVC)**
before starting acquisition. For example, `30` displays a dashed yellow reference
at 30% MVC across the force plot. The target settings are saved with each trial.
The force calibration factors should correspond to the channels' MVC values for
the displayed force percentages to represent MVC percentages.

The feedback tab contains force and live stacked EMG. In **Acquisition**, press
**Choose** beside **Preview EMG channels** to select electrodes by grid/channel.
The field also accepts calibration row lists (e.g. `1 65` displays G1 channel 1
and G2 channel 1). Changing grid count defaults to every eighth electrode
(`1:8:128` for two grids).
Preview selection does not change the electrodes used for decoding or recording.
The preview is decimated to at most 500 points/second per electrode; the shared
DataRecording stacked-plot helper preserves raw amplitudes with vertical offsets.

Uncheck **Plot live feedback** to pause the main force and EMG plots and skip
EMG preview preparation. Acquisition, decomposition and recording continue.
Separate feedback windows keep updating. Recheck it to resume with current data.

**Raster**, **Quadrant**, and **Firing rates** create separate
windows only when clicked. Repeated clicks
bring the existing window forward. Closing these windows does not stop acquisition
or recording; they can be reopened, including after acquisition has stopped.
The Raster window has a multi-select MU list (Ctrl/Shift-click) and a
**Select all MUs** button. Rows retain grid/MU order, from bottom to top.
Each row has at least 28 pixels of space; the plot scrolls vertically when needed.
Selection affects only this display, persists when reopening the window, and
resets to all MUs when a new acquisition starts. Every MU is still decoded and recorded.
**Experimental task** opens a separate window next to **Firing rates**.
Choose two MUs from any grid, then check their reference rates and gains. The
reference fields start from the imported MU rates (or example rates in
Simulation), can be entered manually, or can be captured during a steady
contraction. Capture uses spikes per second over the captured sample windows.
Enter the reference force in % MVC if known; no reference force is assumed.
The experimental cursor uses `smoothed rate / reference rate * gain` on each
axis. The ordinary Quadrant window continues to show firing rates in pps.

Start acquisition in the main window to see the live cursor and trail with
the applied references, gains and smoothing. Use **Apply settings** to commit
edits before starting a task. **Cursor history (s)** sets the visible trail
duration for both preview and trials (default 1 second). This preview shows both firing
rates in pps and does not score or start a recording. When ready, press
**Start task** in the task window. Start task begins a separate recording block; finish any existing
recording first. In Simulation, the two selected simulated units follow the
rest and target cues automatically. Replay uses the stored signals, so a
replayed contraction may not follow the experimental cues.

The default protocol presents TI (1,0), TII (1,1), and TIII (0,1) ten times
each in randomized order, with a recorded seed. The target radius is 0.10,
the angular region starts at radius 0.40, and target and angle holds each
require 0.875 s. Angle hits are scored separately; an active target hit or
20 s timeout ends the attempt. A continuous 2 s hold at the origin starts
each attempt. Timings use elapsed EMG samples and are evaluated once per
acquisition block (128 ms by default); actual cue-to-display latency has not
been measured on hardware. The defaults for the rate window and smoothing
are 1 s and six estimates. Force is displayed separately and does not score
the task.

The block ends and the recording is finalized when all attempts finish or
the task, recording or acquisition is stopped. Closing the task window
stops its block too. Existing auto-save and **Save selected** controls apply.
`task_data.task` contains the settings, MU identities, seeded schedule,
per-block rates and cursor, trial times, intended and unintended hits,
nearest misses, and the completion status. The usual spike and force data
are saved in `task_data.fulltask_data`.

Quadrant feedback starts when its window opens. Its settings panel lets you
choose X/Y MUs by grid and MU label, set rate window, smoothing, cursor history,
and **Reference scale** (default 1.5). Each axis is fixed at 0 to the selected MU's
reference firing rate multiplied by this scale, following I-Spin. The cursor
coordinates remain smoothed firing rates in pps; values are not divided by a
reference or multiplied by a cursor gain. Different references give different
numerical axis ranges while the plotting area stays square. The 30/60-degree
reference lines are scaled to those separate ranges.
Imported references use the retained MUs' `edition.mean_fr`, with missing values
calculated as `mean(fsamp ./ diff(dischargeTimes))`. Padded MU cells are ignored.
Simulation uses illustrative reference rates. Selected references and maxima are
shown in Settings; recorded configuration and grid results retain the references.
Smoothing continues to average recent raw rate estimates, rather than reproducing
the original I-Spin recursive smoothing/startup behaviour.
Press **Apply settings** to update feedback.
Settings persist across popup closure and are saved in subsequent recordings.
They are locked during recording; stop the recording first to adjust them.
Applying changes restarts the feedback history.
The control panel also includes a live two-row discharge raster for only the
applied X/Y motor units, labeled by grid and MU. Applying a different pair updates
this raster without changing acquisition or the recorded motor-unit selection.
The pulse-train tab provides a separate MU selector. Plot history
is bounded independently of recorded data. Quadrant feedback uses the existing
I-Spin-style spike-count window and smoothing; acquisition itself calls the
unchanged I-Spin `getMUfilters`, `getonlineparameters`, and `getspikesonline`.

## Saved results and recovery

Regular recordings contain `data_out`; experimental task recordings contain
`task_data`. Both include configuration, source/calibration file
references, participant/session/trial metadata, source mode, and:

- `online.EMG`: selected stream electrodes, if EMG retention was enabled.
- `online.Pulsetrain`, `Distime`, `Dischargetimes`, `fr`, `mean_fr`, and `Time`:
  combined MU results, ordered by grid then retained MU.
- `online.muMap`: `[grid, retained MU]` for each combined MU column.
- `online.gridResults{g}`: that grid's EMG, pulses, discharges, rates, mask,
  decoder parameters, channel mapping, and original offline MU IDs.
- `online.force`: calibrated values, Arduino timestamps, host session timestamps,
  recording-relative timestamps, calibration, and a simulated-force flag.

EMG time follows sample count. Hardware force arrives asynchronously: the host
timestamps are observation times, and the original Arduino timestamps are also
retained. The two devices do not share a hardware synchronization clock.

Simulation/replay outputs are explicitly marked; replay force is synthetic.
Completed recordings remain available in `onlineApp.Recordings`, with the latest
in `onlineApp.LastResults`. Use **Save selected** to save a completed recording
manually. A failed save leaves its data in memory. Closing the app prompts to
save any unsaved recordings. Save writes a temporary MAT file before moving it
to its final name. No base-workspace variables are overwritten.

## Validation and code organization

- `OnlineDecompositionApp`: controls, file imports, configuration, and saving.
- `OnlineAcquisitionSession`: device/replay/simulation acquisition and recording.
- `OnlineAppDashboard`: embedded displays.
- `collect_app_recording`: builds a recording's result structure.

`test_multigrid_online` exercises I-Spin equivalence, independent routing and
buffers, empty grids, and replay. `test_online_app` exercises simulation,
recording boundaries, force zero/capacity, actual UI buttons, MAT saving, and
exports `tmp/online_app_validation/app_preview.png`. Neither test connects to
hardware. Library and DataRecording source files are reused without edits.
