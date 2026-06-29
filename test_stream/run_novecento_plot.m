 % RUN_NOVECENTO_PLOT
% -------------------------------------------------------------------------
% Main entry point for reading live Novecento+ EMG data and plotting it.
%
% Before running:
%   1. Connect Novecento+ by ethernet.
%   2. Adjust the config values below if your input/channel setup changes.
%   3. Run this script from MATLAB.
%
% Keyboard shortcuts while the plot window is open:
%   r = mark the start sample
%   q = mark the stop sample and create trimmedEMG
%   close figure = stop Novecento streaming safely

cfg = struct();

% Connection timeout. IP 169.254.1.10 and port 23456 are fixed in
% novecento_connect.m.
cfg.socketTimeoutSec = 100;

% Inputs and channels.
cfg.activeInputs = 1;
cfg.emgChannels = 1:64;
cfg.previewChannels = 1:4:64;

% Timing.
cfg.blockDurationSec = 1;
cfg.visibleWindowSec = 5;

% Novecento conversion and packet geometry.
cfg.GainFactor = 0.2861;
cfg.FSelAux = 2;
cfg.forceInputChannelCounts = [];

% Hardware query.
cfg.hardwareQueryRetries = 3;
cfg.hardwareQueryPauseSec = 0.2;

% Analog output.
cfg.AnOutINSource = 0;
cfg.AnOutChan = 1;
cfg.AnOutGain = bin2dec('00000000');

% Per-input device settings.
cfg.IN_Active = zeros(10, 1);
cfg.Mode = zeros(10, 1);
cfg.Gain = zeros(10, 1);
cfg.HRES = zeros(10, 1);
cfg.HPF = zeros(10, 1);
cfg.FsampCode = zeros(10, 1);

cfg.IN_Active(cfg.activeInputs) = 1;
cfg.Gain(cfg.activeInputs) = 1;
cfg.HRES(cfg.activeInputs) = 1;
cfg.HPF(cfg.activeInputs) = 1;
cfg.FsampCode(cfg.activeInputs) = 1; % 2000 Hz

novecento_live_plot(cfg);
