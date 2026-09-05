# Force and EMG Recording

MATLAB tools for calibrating three force sensors and recording force together
with high-density EMG from a Novecento device. Recordings can be saved in a
MUedit-compatible structure for later decomposition and analysis.

## Main files

- `CalibrateForce.m` — calibrates the three force channels and saves a
  participant calibration file.
- `StreamEmgAndForce.m` — defines the recording configuration and launches the
  force-and-EMG recorder.
- `StreamOnlyForce.m` — records force without Novecento EMG.

## Configure and run

Open `StreamEmgAndForce.m` and review:

- `config.arduinoPort`
- `config.maxDurationSec`
- `config.emgEnabled`
- `config.emgActiveInputs`
- `config.emgChannels`
- `config.emgPreviewRows`
- `config.muEditGridName`
- `config.muEditMuscle`
- Force-calibration settings

Then run:

```matlab
StreamEmgAndForce