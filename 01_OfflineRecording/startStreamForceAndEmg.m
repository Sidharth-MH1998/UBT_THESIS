%% prepare workspace
clear;
close all;
clc;
% serialportlist("available")

%% User Config
% force sensors
config = struct();
config.arduinoPort = 'COM4'; % Arduino force acquisition
config.forceFs = 50;
config.maxDurationSec = 5 * 60;

% Novecento EMG acquisition
config.emgEnabled = true;
config.emgActiveInputs = 1;       % Use [1 2] for two active inputs
config.emgChannels = 1:64;        % Channels retained from the live stream
config.emgPreviewRows = 1:4:64;   % Channels displayed in the preview
config.emgBlockDurationSec = 0.02; % EMG duration from Novecento (20ms)
config.emgPlotUpdateRate = 10;     % Emg plot refresh rate
config.emgDisplayDecimation = 10;  % fs /10 pints are plotted

% Live display
config.displayTimeSec = 15;
config.bufferTimeSec = 5;  %future horizontal space shown on the force plot.
config.forcePlotUpdateRate = 10; % force plot refresh rate

% MUedit-compatible saved structure
config.muEditGridName = 'GR08MM1305';
config.muEditMuscle = 'Forearm Flexor';  % Change to the recorded muscle

% Force calibration
config.forceCalibrationFile = ''; % Leave empty to show the calibration-file selector at startup.
config.promptForceCalibration = true;
config.defaultCalibrationFactors = [10 10 10];
config.defaultZeroValues = [0 0 0];
config.defaultReverseStates = [false false false];

%% Run the main recorder
StreamForceAndEmgV2(config);
