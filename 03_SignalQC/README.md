# EMG signal quality checks

## Scripts

### [Live quality check](LiveQualityCheck.m)

`LiveQualityCheck.m` streams EMG from the Novecento+, displays live traces and grid heatmaps, and reports signal quality metrics and potentially bad channels.

### [Recorded signal quality check](qualitycheck.m)

`qualitycheck.m` opens a saved EMG recording, compares traces and spectra before and after filtering, and flags potentially bad channels. It also plots force when available.

### [Bad-channel detection](FindBadchan.m)

`FindBadchan.m` is a function used by both scripts. It takes an EMG matrix with channels as rows and returns candidate bad-channel indices and a diagnostic report.

## Run order

- Run `LiveQualityCheck.m` to check signals from a connected Novecento+.
- Run `qualitycheck.m` and select a MAT-file to review a saved recording.
