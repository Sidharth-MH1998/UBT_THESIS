clc
close all
clear
% serialportlist("available")

%% Force acquisition and recording duration
% Set the Arduino port, sampling rate, and recording limit.
config = struct();
config.arduinoPort = 'COM4'; % Arduino force acquisition
config.forceFs = 50; % plotted at 10 Hz
config.maxDurationSec = 5 * 60;

%% Novecento EMG acquisition
numberOfGrids = 2;              % Generates active inputs, EMG channels and grid metadata
gridName = 'GR08MM1305';         % Same electrode-grid model for every grid
muscleNames = {'flexor 1', 'flexor 2'};        % Enter one muscle name per grid, in grid order

assert(isscalar(numberOfGrids) && ismember(numberOfGrids, 1:10),'numberOfGrids must be an integer from 1 to 10.');
config.emgEnabled = true;

config.emgActiveInputs = 1:numberOfGrids; % Physical inputs; adjust if using e.g. [4 5 6]
% Each 64-electrode probe contributes 70 stream channels; retain the first 64.

config.emgChannels = reshape((1:64).' + 70*(0:numberOfGrids-1), 1, []);
config.emgPreviewRows = 1:8:128;   % Channels displayed in the preview
config.emgBlockDurationSec = 0.02; % Novecento EMG block duration (20 ms)
config.emgPlotUpdateRate = 10;     % EMG plot refresh rate
config.emgDisplayDecimation = 10;  % Plot every tenth EMG sample

%% Live display
config.displayTimeSec = 8;
config.bufferTimeSec = 5;         % Time shown ahead of the force trace
config.forcePlotUpdateRate = 10; % force plot refresh rate

%% MUedit recording metadata
config.muEditGridName = repmat({gridName}, 1, numberOfGrids);

assert(iscellstr(muscleNames) && numel(muscleNames) == numberOfGrids,'Enter one muscle name per grid in muscleNames.');
config.muEditMuscle = muscleNames;

%% Force calibration
config.forceCalibrationFile = ''; % Leave empty to show the calibration-file selector at startup.
config.promptForceCalibration = true;
config.defaultCalibrationFactors = [10 10 10];
config.defaultZeroValues = [0 0 0];
config.defaultReverseStates = [false false false];

%% Start recording
StreamForceAndEmg(config);
