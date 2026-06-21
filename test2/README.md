# Simple Novecento real-time plotting

This folder is self-contained.

- `run_novecento_live.m` connects directly to Novecento+, uses `CRC8.m`,
  decodes raw EMG using the OTB reference packet format, and plots it live.
- `replay_otb_mat_realtime.m` loads `recordedEMG` from an OTB MAT file and
  replays it as a real-time plot without connecting to the device.

Run one of these from MATLAB:

```matlab
run_novecento_live
replay_otb_mat_realtime
```

Neither script applies software filtering.

For display only, each waveform is centered and normalized around its
channel number on the y-axis. This prevents large raw amplitudes from
overlapping neighboring channels. The acquired data is not changed.
