# Pseudo-online EMG decomposition

## Scripts

### [Pseudo-online decomposition](pseudo_online_with_force_v3.m)

`pseudo_online_with_force_v3.m` processes a recorded EMG trial in short windows using motor unit filters from a calibration file. It plots motor unit activity with an optional force overlay and stores discharge times, pulse trains, and firing rates in the MATLAB workspace.

### [Offline comparison](compare_offline_pseudo_online.m)

`compare_offline_pseudo_online.m` matches motor units against an offline decomposition of the same trial and reports spike-timing agreement.

## Run order

1. Run `pseudo_online_with_force_v3.m` and select the calibration file and recorded trial.
2. Make the offline reference for that trial available in the same MATLAB workspace, then run `compare_offline_pseudo_online.m`.
