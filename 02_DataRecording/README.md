# Data recording

## Scripts

### [Force calibration](CalibrateForce.m)

`CalibrateForce.m` calibrates and zeros the three force sensors and saves their calibration settings to a MAT-file.

### [EMG and force recording](StreamEmgAndForce.m)

`StreamEmgAndForce.m` configures and starts simultaneous recording from the Novecento EMG system and the Arduino force sensors.

### [EMG-only recording](StreamOnlyEmg.m)

`StreamOnlyEmg.m` displays live Novecento EMG and saves the recording segment marked with `r` and `q`.

### [Force-only recording](StreamOnlyForce.m)

`StreamOnlyForce.m` displays and records force from three load cells, with optional target tracking.

## Run order

1. For force calibration, use an existing calibration file or create one with `CalibrateForce.m`.
2. Run the recording script for the signals you want to collect.
