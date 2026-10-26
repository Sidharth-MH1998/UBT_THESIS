# Online decomposition app

Run `StartOnlineApp` from this folder. The workspace variable `onlineApp` holds
the app. The existing script launcher and standalone demo remain available.

## Sources

- **Simulation** generates three synthetic MUs per configured grid and three
  synthetic force channels. It requires no files or hardware. This exercises
  the interface and recording workflow, rather than EMG decoding accuracy.
- **Replay calibration** processes the imported recording's EMG window by window
  through the actual per-grid I-Spin decoders. Force is simulated. Replay ends
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
and G2 channel 1). Changing grid count defaults to the first channel of each grid.
Preview selection does not change the electrodes used for decoding or recording.
The preview is decimated to at most 500 points/second per electrode; the shared
DataRecording stacked-plot helper preserves raw amplitudes with vertical offsets.

**Open raster**, **Open quadrant**, and **Open firing rates** create separate
windows only when clicked. Repeated clicks
bring the existing window forward. Closing these windows does not stop acquisition
or recording; they can be reopened, including after acquisition has stopped.
Quadrant feedback starts when its window opens. Its settings panel lets you
choose X/Y MUs by grid and MU label, set rate window, smoothing, cursor history,
and axis maximum (`0` means automatic). Press **Apply settings** to update feedback.
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

Each MAT file contains `data_out` with configuration, source/calibration file
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
