# Online EMG decomposition app

The MATLAB app decodes motor-unit activity from multiple EMG grids in real time and displays it alongside force for biofeedback.

## Get started

Run [`StartOnlineApp.m`](StartOnlineApp.m), choose a source, and press **Start acquisition**.

- **Simulation** uses synthetic motor-unit and force signals without hardware or calibration files.
- **Replay calibration** runs the decoder on EMG from an imported decomposition file and replays recorded force when available.
- **Hardware** uses live Novecento EMG and Arduino force with an imported edited decomposition.

## Features

- Live force and EMG previews with selectable EMG channels and an optional force target.
- Separate windows for motor-unit rasters, firing rates, and two-motor-unit quadrant feedback.
- An experimental target task with separate researcher controls and participant feedback.
- Trial recording and MAT-file export with optional autosave.

## Tests

Hardware-free test functions are in `TestScripts`, separate from `OnlineDecomposeSrc`.
From the repository root, run a test with:

```matlab
addpath(fullfile('07_onlineDecompositionV3','TestScripts'));
test_experimental_task
```

Each test adds the app source folder to the MATLAB path automatically.


