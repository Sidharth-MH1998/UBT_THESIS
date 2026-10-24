clc
close all
clear
% serialportlist("available")

%% User Config
% force sensors
config = struct();
config.arduinoPort = 'COM4'; % Arduino force acquisition
config.forceFs = 50;
config.maxDurationSec = 5 * 60;

% Novecento EMG acquisition
numberOfGrids = 1;              % Generates active inputs, EMG channels and grid metadata
gridName = 'GR08MM1305';         % Same electrode-grid model for every grid
muscleNames = {'flexor'};        % Enter one muscle name per grid, in grid order

assert(isscalar(numberOfGrids) && ismember(numberOfGrids, 1:10),'numberOfGrids must be an integer from 1 to 10.');
config.emgEnabled = true;

config.emgActiveInputs = 1:numberOfGrids; % Physical inputs; adjust if using e.g. [4 5 6]
% Each 64-electrode probe contributes 70 stream channels; retain the first 64.

config.emgChannels = reshape((1:64).' + 70*(0:numberOfGrids-1), 1, []);
config.emgPreviewRows = 1:8:128;   % Channels displayed in the preview
config.emgBlockDurationSec = 0.02; % EMG duration from Novecento (20ms)
config.emgPlotUpdateRate = 10;     % Emg plot refresh rate
config.emgDisplayDecimation = 10;  % fs /10 pints are plotted

% Live display
config.displayTimeSec = 8;
config.bufferTimeSec = 5;  %future horizontal space shown on the force plot.
config.forcePlotUpdateRate = 10; % force plot refresh rate

% MUedit-compatible saved structure
config.muEditGridName = repmat({gridName}, 1, numberOfGrids);

assert(iscellstr(muscleNames) && numel(muscleNames) == numberOfGrids,'Enter one muscle name per grid in muscleNames.');
config.muEditMuscle = muscleNames;

% Force calibration
config.forceCalibrationFile = ''; % Leave empty to show the calibration-file selector at startup.
config.promptForceCalibration = true;
config.defaultCalibrationFactors = [10 10 10];
config.defaultZeroValues = [0 0 0];
config.defaultReverseStates = [false false false];

%% Run the main recorder
StreamForceAndEmg(config);
