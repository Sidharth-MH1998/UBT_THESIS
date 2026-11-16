clc
close all
clear
% serialportlist("available")

%% User Config
recruitmentDir = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(recruitmentDir), '07_onlineDecompositionV3'));
setup_online_dependencies();

% Novecento EMG acquisition (same configuration builder as DataRecording)
numberOfGrids = 2;
assert(isscalar(numberOfGrids) && ismember(numberOfGrids, 1:10), ...
    'numberOfGrids must be an integer from 1 to 10.');
activeInputs = 1:numberOfGrids; % Physical inputs, in calibration grid order
% Every 70-channel probe has 64 electrodes followed by 6 auxiliary channels.
emgChannels = reshape((1:64).' + 70*(0:numberOfGrids-1), 1, []);
blockDurationSec = 0.128;
cfg = makeNovecentoConfig(blockDurationSec, activeInputs, emgChannels);
cfg.calibChannels = 1:(64 * numberOfGrids);
cfg.windowBaseCols = round(blockDurationSec * 500);
cfg.forceInputChannelCounts = zeros(1,10);
cfg.forceInputChannelCounts(activeInputs) = 70;
cfg.onlineDurationSec = inf;    % Stop manually, or enter a duration in seconds
cfg.recordEMG = true;          % Retain online EMG in data_out

% Arduino force acquisition
cfg.forcePort = 'COM3';
cfg.forceFs = 50;
cfg.forceMaxDurationSec = 10 * 60;

% Live display
cfg.visibleWindowSec = 10;
cfg.showLegend = true;
cfg.frYLim = 60;                % Firing-rate upper limit in Hz
cfg.printEveryNWindows = 10;
cfg.forceDisplayTimeSec = 15;
cfg.forceBufferTimeSec = 5;     % Future horizontal space on the force plot
cfg.forcePlotRateHz = 10;

% Force calibration
cfg.forceCalibrationFile = ''; % Empty opens the calibration-file selector
cfg.forcePromptCalibration = true;
cfg.forceDefaultCalibrationFactors = [10 10 10];
cfg.forceDefaultZeroValues = [0 0 0];
cfg.forceDefaultReverseStates = [false false false];

%% Load decomposition calibration
[matFileName, matFolder] = uigetfile('*.mat', ...
    'Select decomposed or edited MUedit file');
if isequal(matFileName, 0)
    disp('No MUedit file selected. Online decomposition cancelled.');
    return;
end

matFile = fullfile(matFolder, matFileName);
calibrationSession = load(matFile, 'signal', 'parameters', 'edition');
assert(isfield(calibrationSession, 'signal') && ...
    isfield(calibrationSession, 'parameters'), ...
    'Calibration file must contain signal and parameters.');
calibration_data = calibrationSession.signal;
parameters = calibrationSession.parameters;
assert(numel(calibration_data.EMGmask) == numberOfGrids, ...
    'Calibration grid count must match numberOfGrids.');
calibration_data.onlineMUOriginalIDs = cell(1,numberOfGrids);
for gridIdx = 1:numberOfGrids
    calibration_data.onlineMUOriginalIDs{gridIdx} = ...
        1:size(calibration_data.Pulsetrain{gridIdx},1);
end

% Use edited pulse trains and discharge times when available.
if isfield(calibrationSession, 'edition')
    editedMUFields = {'Pulsetrain', 'Dischargetimes'};
    for fieldIdx = 1:numel(editedMUFields)
        fieldName = editedMUFields{fieldIdx};
        if isfield(calibrationSession.edition, fieldName)
            calibration_data.(fieldName) = calibrationSession.edition.(fieldName);
        end
    end
    for gridIdx = 1:numberOfGrids
        nMU = size(calibration_data.Pulsetrain{gridIdx},1);
        calibration_data.onlineMUOriginalIDs{gridIdx} = 1:nMU;
        statsField = sprintf('grid%d', gridIdx);
        if isfield(calibrationSession.edition, 'edit_stats') && ...
                isfield(calibrationSession.edition.edit_stats, statsField) && ...
                isfield(calibrationSession.edition.edit_stats.(statsField), ...
                    'quality_filter_kept_mu')
            calibration_data.onlineMUOriginalIDs{gridIdx} = ...
                calibrationSession.edition.edit_stats.(statsField).quality_filter_kept_mu;
        end
    end
    disp('Using edited decomposition data.');
else
    disp('Using non-edited decomposition data.');
end
fprintf('Loaded calibration file: %s\n', matFile);

%% Recruitment recording settings
cfg.outputFolder = fullfile(recruitmentDir, 'recordings');
cfg.muEditGridName = repmat({'GR08MM1305'}, 1, numberOfGrids);
cfg.muEditMuscle = repmat({'flexor'}, 1, numberOfGrids); % Set one per grid
cfg.decompositionCalibrationFile = matFile;

%% Run recruitment recorder
% Record/Track Record saves individual trials in cfg.outputFolder.
data_out = record_mu_recruitment(calibration_data, parameters, cfg);
