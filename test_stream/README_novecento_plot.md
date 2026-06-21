# Novecento live plot code

Run `run_novecento_plot.m` from MATLAB to connect to Novecento+, read EMG data, and show a live stacked plot.
The pipeline displays and records decoded raw EMG without software filtering.
For display only, each waveform is centered, normalized, clipped, and plotted
around its channel number on the y-axis. Stored EMG values remain unchanged.

## Files

- `run_novecento_plot.m` - main script with the settings you normally edit.
- `novecento_live_plot.m` - session loop, live plotting, and keyboard markers.
- `novecento_connect.m` - TCP connection, hardware query, and packet layout setup.
- `novecento_read_emg_block.m` - reads one block and converts it to channels x samples.
- `novecento_plot_stacked.m` - stacked channel plotting helper.
- `novecento_disconnect.m` - stops streaming safely.
- `CRC8.m` - CRC function from the original Novecento reference code.

## MATLAB outputs

During the session these variables are kept in the base workspace:

- `recordedEMG`
- `recordedDurationSec`
- `recordStartSample`
- `recordEndSample`
- `trimmedEMG`

`recordedEMG` and `trimmedEMG` contain the decoded raw signal displayed by the live plot.

Press `r` to mark the start of a trial and `q` to mark the end. After pressing `q`, the trimmed variables contain the selected data.
