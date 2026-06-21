# Novecento live plot code

Run `run_novecento_plot.m` from MATLAB to connect to Novecento+, read EMG data, and show a live stacked plot.
The pipeline displays and records decoded raw EMG without software filtering.
For display only, each waveform is centered, normalized, clipped, and plotted
around its channel number on the y-axis. Stored EMG values remain unchanged.

## Files

- `run_novecento_plot.m` - readable config/start script. Edit this file for
  channels, timing, filtering, and Novecento input settings.
- `novecento_emg_live_session.m` - combined implementation file with preflight
  checks, session loop, live plotting, TCP connection, hardware query, packet
  decoding, marker handling, and safe disconnect helpers.
- `CRC8.m` - CRC function from the original Novecento reference code.

## MATLAB outputs

During the session these variables are kept in the base workspace:

- `recordedEMG`
- `recordedDurationSec`
- `recordStartSample`
- `recordEndSample`
- `trimmedEMG`

`recordedEMG` and `trimmedEMG` contain the decoded raw signal. If
`cfg.filterLivePlot = true`, only the live display is filtered with adaptive
notch plus band-pass filtering; the saved workspace variables stay raw.

Press `r` to mark the start of a trial and `q` to mark the end. After pressing `q`, the trimmed variables contain the selected data.
