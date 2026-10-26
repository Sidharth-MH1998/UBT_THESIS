
function out = online_decompositionV3(signal,parameters,cfg)
% online_decompositionV3 online MU decomposition with live force.
%
%   out = online_decompositionV3(signal,parameters,cfg)
%


setup_online_dependencies();
forceCfg = cfg;

forceState = initialize_force_acquisition(forceCfg); % initialise force calibrations

forceTimer = timer( ...
    'ExecutionMode','fixedSpacing', ...
    'Period',1/forceCfg.forceFs, ...
    'BusyMode','drop', ...
    'TimerFcn',@read_force_callback, ...
    'ErrorFcn',@force_timer_error);
forceState.timer = forceTimer;
cleanupObj = onCleanup(@() cleanup_force_resources( ...
    forceTimer,forceState.serialObj,forceState.fig));
forceState.sessionClock = tic;
start(forceTimer);

% Run multi-grid decomposition while the force timer reads Arduino samples.
sharedUI = struct('fig',forceState.fig, ...
    'axRaster',forceState.controls.axRaster, ...
    'pollForce',@read_force_callback);
out = onlineDecompositionStream(signal,parameters,cfg,sharedUI);

stop(forceTimer);
out.online.force = export_force_state(forceState,forceCfg);

    function read_force_callback(~, ~)
        if ~ishandle(forceState.fig)
            stop(forceState.timer);
            return;
        end

        c = forceState.controls;
        if c.btnClose.Value % check whether stop requested
            setappdata(forceState.fig, 'forceStopRequested', true);
            stop(forceState.timer);
            return;
        end

        update_sign_label();

        while forceState.serialObj.NumBytesAvailable > 0 % read arduino data
            serialLine = readline(forceState.serialObj);
            sample = sscanf(char(serialLine), '%f,%f,%f,%f');
            if numel(sample) < 4
                continue;
            end

            raw = reshape(sample(2:4), 1, []);
            raw(forceState.reverseStates) = -raw(forceState.reverseStates);
            if c.forceSignCheckbox.Value
                raw = -raw;
            end
            forceState.lastRawSample = raw;

            calibrated = (raw - forceState.zeroValues) ./ ...
                forceState.calibrationFactors * 100;
            if forceState.nSamples > 0
                calibrated = 0.3 * calibrated + ...
                    0.7 * forceState.forceData(forceState.nSamples, :);
            end

            if forceState.nSamples < size(forceState.forceData, 1)
                forceState.nSamples = forceState.nSamples + 1;
                forceState.forceData(forceState.nSamples, :) = calibrated;
                forceState.arduinoTime(forceState.nSamples) = sample(1);
                forceState.sessionTime(forceState.nSamples) = toc(forceState.sessionClock);
            elseif ~forceState.bufferWarningShown
                warning('Force buffer is full; additional samples are not stored.');
                forceState.bufferWarningShown = true;
            end
        end

        if c.btnZero.Value
            forceState.zeroValues = forceState.lastRawSample;
            c.btnZero.Value = false;
            disp('Force channels zeroed.');
        end

        if c.btnRecord.Value
            c.ax.Color = [1 0.95 0.9];
        elseif c.btnRecordTracking.Value
            c.ax.Color = [0.9 1 0.9];
        else
            c.ax.Color = [1 1 1];
        end

        if forceState.nSamples - forceState.lastPlotSample >= forceState.plotInterval
            target = str2double(c.forceTargetBox.String);
            if isnan(target)
                target = 100;
            end
            updateStreamForcePlot(c.ax, forceState.lines, forceState.forceData, ...
                forceCfg.forceFs, 3, forceCfg.forceDisplayTimeSec, ...
                forceCfg.forceBufferTimeSec, target, 0, forceState.nSamples);
            forceState.lastPlotSample = forceState.nSamples;
        end
    end

    function update_sign_label()
        currentSignState = forceState.controls.forceSignCheckbox.Value;
        if currentSignState == forceState.lastSignState
            return;
        end
        forceState.lastSignState = currentSignState;
        if currentSignState
            forceState.controls.forceSignLabel.String = sprintf('%s\n%s', ...
                '(+): Extension', '(-): Flexion ');
        else
            forceState.controls.forceSignLabel.String = sprintf('%s\n%s', ...
                '(+): Flexion', '(-): Extension ');
        end
    end

    function force_timer_error(~, event)
        warning('Force stream timer stopped: %s', event.Data.Message);
    end

end


%% Helper to init force acquisition

function forceState = initialize_force_acquisition(cfg)
[calibrationFactors, zeroValues, reverseStates] = load_force_calibration(cfg);
[fig, controls] = setup_force_figure();

serialObj = [];
try
    serialObj = initializeArduinoForceStream(cfg.forcePort);
catch ME
    if ~isempty(serialObj)
        try
            delete(serialObj);
        catch
        end
    end
    if ishandle(fig)
        delete(fig);
    end
    rethrow(ME);
end

maxSamples = round(cfg.forceFs * cfg.forceMaxDurationSec);
forceState = struct();
forceState.fig = fig;
forceState.controls = controls;
forceState.serialObj = serialObj;
forceState.timer = [];
forceState.sessionClock = [];
forceState.calibrationFactors = reshape(calibrationFactors, 1, 3);
forceState.zeroValues = reshape(zeroValues, 1, 3);
forceState.reverseStates = logical(reshape(reverseStates, 1, 3));
forceState.forceData = zeros(maxSamples, 3);
forceState.arduinoTime = zeros(maxSamples, 1);
forceState.sessionTime = zeros(maxSamples, 1);
forceState.nSamples = 0;
forceState.lastRawSample = zeros(1, 3);
forceState.lastSignState = controls.forceSignCheckbox.Value;
forceState.plotInterval = max(1, round(cfg.forceFs / cfg.forcePlotRateHz));
forceState.lastPlotSample = 0;
forceState.lines = initializeStreamForcePlot(controls.ax, 3);
forceState.bufferWarningShown = false;
setappdata(fig, 'forceStopRequested', false);
end


%% helper to load force calibrations
function [factors, zeroValues, reverseStates] = load_force_calibration(cfg)
factors = cfg.forceDefaultCalibrationFactors;
zeroValues = cfg.forceDefaultZeroValues;
reverseStates = cfg.forceDefaultReverseStates;
calibrationFile = cfg.forceCalibrationFile;
% if no calibration file in config opens uigetfile 
if isempty(calibrationFile) && cfg.forcePromptCalibration
    [name, folder] = uigetfile('*.mat', ...
        'Select force calibration file, or press Cancel to use defaults');
    if ~isequal(name, 0)
        calibrationFile = fullfile(folder, name);
    end
end

if isempty(calibrationFile)
    disp('No force calibration selected. Using default values.');
    return;
end

data = load(calibrationFile,'calibrationFactors', 'zeroValues', 'reverseStates');
required = {'calibrationFactors', 'zeroValues', 'reverseStates'}; % validation 
for i = 1:numel(required)
    if ~isfield(data, required{i})
        error('Calibration file is missing %s.', required{i});
    end
end
factors = data.calibrationFactors;
zeroValues = data.zeroValues;
reverseStates = data.reverseStates;
fprintf('Loaded force calibration values: %s\n', calibrationFile);
end


%% Helper to use force states

function out = export_force_state(forceState, cfg)
n = forceState.nSamples;
out = struct();
out.data = forceState.forceData(1:n, :);
out.arduinoTime = forceState.arduinoTime(1:n);
out.sessionTime = forceState.sessionTime(1:n);
out.fs = cfg.forceFs;
out.calibrationFactors = forceState.calibrationFactors;
out.zeroValues = forceState.zeroValues;
out.reverseStates = forceState.reverseStates;
end

function cleanup_force_resources(forceTimer, serialObj, fig)
try
    if ~isempty(forceTimer) && isvalid(forceTimer)
        stop(forceTimer);
        delete(forceTimer);
    end
catch
end
try
    if ~isempty(serialObj) && isvalid(serialObj)
        delete(serialObj);
    end
catch
end
try
    if ishandle(fig)
        delete(fig);
    end
catch
end
end


%% Helper to create the figure 

function [fig, c] = setup_force_figure()
% Reuse the recorder UI; its EMG preview axes display the online raster.
[fig, c.ax, c.axRaster, c.btnClose, c.btnZero, c.btnRecord, ...
    c.btnRecordTracking, c.forceChanDropdown, c.traceTypeDropdown, ...
    c.tWaitBox, c.tSlopeBox, c.tPlateauBox, c.forceTargetBox, ...
    c.forceSignLabel, c.forceSignCheckbox, c.participantIDBox, ...
    c.trialBox, c.sessionBox] = setupRecordingFigure(true, 0);
fig.Name = 'Force and Real-Time Spike Trains';
title(c.axRaster, 'Live Spike Trains');
ylabel(c.axRaster, 'Motor Unit');
c.forceChanDropdown.Value = 1;
end
