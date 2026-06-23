% RUN_NOVECENTO_PLOT
% -------------------------------------------------------------------------
% Configuration and start script for a live Novecento+ EMG session.
%
% Before running:
%   1. Connect Novecento+ by ethernet.
%   2. Adjust only the config values in this file.
%   3. Run this script from MATLAB.
%
% Keyboard shortcuts while the plot window is open:
%   r = mark the start sample
%   q = mark the stop sample and create trimmedEMG
%   close figure = stop Novecento streaming safely

cfg = struct();

%% Network connection
% Device address is fixed in novecento_emg_live_session.m:
%   IP   = 169.254.1.10
%   Port = 23456
% Increase this timeout if MATLAB stops while waiting for hardware data.
cfg.socketTimeoutSec = 100;

%% Channels to stream, record, and preview
% activeInputs chooses which Novecento input connector(s) are enabled.
% emgChannels chooses which decoded EMG channels are stored.
% previewChannels chooses which stored rows are shown live. Using 1:4:64
% keeps the live plot readable while all 64 channels are still recorded.
cfg.activeInputs = 1;
cfg.emgChannels = 1:64;
cfg.previewChannels = 1:4:64;

%% Timing
% blockDurationSec controls each TCP read size. Use an integer-friendly
% value such as 0.5, 1, or 2 seconds.
% visibleWindowSec controls the plot window length only.
cfg.blockDurationSec = 1;
cfg.visibleWindowSec = 10;

%% Display-only filtering
% These settings affect only the live preview. recordedEMG and trimmedEMG
% stay as decoded raw EMG so analysis/export is not silently altered.
cfg.filterLivePlot = true;
cfg.useAdaptiveNotch = true;
cfg.baseFreqRange = [45 55];
cfg.numHarmonics = 9;
cfg.notchWidth = 1;
cfg.useBandpass = true;
cfg.emgtype = 1; % 1 = surface EMG, 2 = intra-muscular EMG

%% Novecento conversion and packet geometry
% GainFactor converts decoded integer samples into mV.
% FSelAux selects AUX sampling frequency: 1=500 Hz, 2=2000 Hz,
% 3=4000 Hz, 4=8000 Hz.
% forceInputChannelCounts is normally empty. Use it only if the device
% hardware query reports the wrong channel count.
cfg.GainFactor = 0.2861;
cfg.FSelAux = 2;
cfg.forceInputChannelCounts = [];

%% Hardware query retry behavior
% The session asks the device which probes are connected before streaming.
cfg.hardwareQueryRetries = 3;
cfg.hardwareQueryPauseSec = 0.2;

%% Analog output
% Leave these unchanged unless you intentionally use Novecento analog out.
cfg.AnOutINSource = 0;
cfg.AnOutChan = 1;
cfg.AnOutGain = bin2dec('00000000');

%% Per-input device settings
% Ten entries are required because Novecento has ten possible inputs.
% The active input(s) below are filled after the vectors are created.
cfg.IN_Active = zeros(10, 1);
cfg.Mode = zeros(10, 1);
cfg.Gain = zeros(10, 1);
cfg.HRES = zeros(10, 1);
cfg.HPF = zeros(10, 1);
cfg.FsampCode = zeros(10, 1);

% Apply the actual settings to each active input.
% Gain = 1 uses the standard device gain.
% HRES = 0 reads 16-bit samples; HRES = 1 reads high-resolution 32-bit data.
% HPF = 1 enables the device high-pass filter.
% FsampCode = 1 means 2000 Hz.
cfg.IN_Active(cfg.activeInputs) = 1;
cfg.Gain(cfg.activeInputs) = 1;
cfg.HRES(cfg.activeInputs) = 0;
cfg.HPF(cfg.activeInputs) = 1;
cfg.FsampCode(cfg.activeInputs) = 1;

%% Start the live session
novecento_emg_live_session(cfg);
