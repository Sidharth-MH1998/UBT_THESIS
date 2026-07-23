 % RUN_NOVECENTO_PLOT
% -------------------------------------------------------------------------
% reading live Novecento+ EMG data and plotting it.
% Keyboard shortcuts while the plot window is open:
%   r = mark the start sample
%   q = mark the stop sample and create trimmedEMG
%   close figure = stop Novecento streaming safely
clear;
close all;
cfg = struct();

% Connection timeout. IP 169.254.1.10 and port 23456 are fixed in
% novecento_connect.m.
cfg.socketTimeoutSec = 100;

% Inputs and channels.
cfg.activeInputs = [1 2];
cfg.emgChannels = [1:64 71:134];
cfg.previewChannels = 1:8:128;

% Timing.
cfg.blockDurationSec = 1;
cfg.visibleWindowSec = 15;

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
cfg.FsampCode(cfg.activeInputs) = 1; % 2000 HzFsampVal = [500 2000 4000 8000];

novecento_live_plot(cfg);