%% Starter configuration for force and EMG recording
clear;
close all;
clc;

config = struct();

% Arduino force acquisition
config.arduinoPort = 'COM4';
config.forceFs = 50;
config.maxDurationSec = 10 * 60;

% Novecento EMG acquisition
config.emgEnabled = true;
config.emgActiveInputs = 1;       % Use [1 2] for two active inputs
config.emgChannels = 1:64;        % Channels retained from the live stream
config.emgPreviewRows = 1:4:64;   % Channels displayed in the preview
config.emgBlockDurationSec = 0.02;
config.emgPlotUpdateRate = 10;
config.emgDisplayDecimation = 10;

% MUedit-compatible saved structure
config.muEditGridName = 'GR08MM1305';
config.muEditMuscle = 'Unknown';  % Change to the recorded muscle

% Live display
config.displayTimeSec = 15;
config.bufferTimeSec = 5;
config.forcePlotUpdateRate = 10;

% Force calibration
config.forceCalibrationFile = ''; % Leave empty to show the calibration-file selector at startup.
config.promptForceCalibration = true;
config.defaultCalibrationFactors = [10 10 10];
config.defaultZeroValues = [0 0 0];
config.defaultReverseStates = [false false false];

%% Run the main recorder
StreamForceAndEmgV2(config);
