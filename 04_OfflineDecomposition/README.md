# Offline EMG decomposition

## Scripts

### [Decomposition launcher](Launchdecomp5.m)

`Launchdecomp5.m` loads an EMG recording, lets you review bad channels and select a segment, then runs the decomposition. It saves a `-decomposed5.mat` file beside the recording and runs automatic editing if enabled.

### [Decompose 5](decompose5.m)

`decompose5.m` extracts motor units from multichannel EMG using FastICA. It removes duplicate units and returns MUedit-compatible results, including pulse trains, discharge times, and firing rates.

## Run order

1. Run `Launchdecomp5.m` and select the recording MAT-file.
2. Review the channels and select the segment to decompose. The launcher calls `decompose5.m` and saves the results.
