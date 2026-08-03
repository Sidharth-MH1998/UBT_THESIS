function out = onlineForceStream(Calib_data, calibEMG_full, fs, badchan, userCfg)
% ONLINEFORCESTREAM Online EMG decomposition with live three-channel force.
%
%   out = onlineForceStream(Calib_data, calibEMG_full, fs, badchan, cfg)
%
% The motor-unit algorithm is the existing Online_decomposition/online_decomp.m.
% Force acquisition runs independently and uses the layout, calibration,
% zeroing, sign convention, smoothing, and scrolling plot from
% experimentSetup/streamForceEMG.m.
%
% Force-specific cfg fields (all optional):
%   forcePort                       default 'COM4'
%   forceFs                         default 50 Hz
%   forceMaxDurationSec             default 600 s
%   forceCalibrationFile            default '' (show file selector)
%   forcePromptCalibration          default true
%   forceDefaultCalibrationFactors  default [10 10 10]
%   forceDefaultZeroValues          default [0 0 0]
%   forceDefaultReverseStates       default [false false false]
%
% Force results are returned in out.online.force.

if nargin < 5 || isempty(userCfg)
    userCfg = struct();
end
if nargin < 4 || isempty(badchan)
    badchan = [];
end

forceCfg = default_force_cfg();
forceCfg = merge_force_cfg(forceCfg, userCfg);

scriptDir = fileparts(mfilename('fullpath'));
addpath(fullfile(scriptDir, 'Online_decomposition'));
addpath(fullfile(scriptDir, 'online_decomp_renato', 'lib'));

state = initialize_force_state(forceCfg);

forceTimer = timer( ...
    'ExecutionMode', 'fixedSpacing', ...
    'Period', 1 / forceCfg.forceFs, ...
    'BusyMode', 'drop', ...
    'TimerFcn', @read_force_callback, ...
    'ErrorFcn', @force_timer_error);
state.timer = forceTimer;
cleanupObj = onCleanup(@() cleanup_force_resources( ...
    forceTimer, state.serialObj, state.fig)); %#ok<NASGU>
state.sessionClock = tic;
start(forceTimer);

% Run the already-implemented decomposition without modifying it.
out = online_decomp(Calib_data, calibEMG_full, fs, badchan, userCfg);

stop(forceTimer);
out.online.force = export_force_state(state, forceCfg);

    function read_force_callback(~, ~)
        if ~ishandle(state.fig)
            stop(state.timer);
            return;
        end

        c = state.controls;
        if c.btnClose.Value
            setappdata(state.fig, 'forceStopRequested', true);
            stop(state.timer);
            return;
        end

        update_sign_label();

        while state.serialObj.BytesAvailable > 0
            sample = fscanf(state.serialObj, '%f,%f,%f,%f');
            if numel(sample) < 4
                continue;
            end

            raw = reshape(sample(2:4), 1, []);
            raw(state.reverseStates) = -raw(state.reverseStates);
            if c.forceSignCheckbox.Value
                raw = -raw;
            end
            state.lastRawSample = raw;

            calibrated = (raw - state.zeroValues) ./ ...
                state.calibrationFactors * 100;
            if state.nSamples > 0
                calibrated = 0.3 * calibrated + ...
                    0.7 * state.forceData(state.nSamples, :);
            end

            if state.nSamples < size(state.forceData, 1)
                state.nSamples = state.nSamples + 1;
                state.forceData(state.nSamples, :) = calibrated;
                state.arduinoTime(state.nSamples) = sample(1);
                state.sessionTime(state.nSamples) = toc(state.sessionClock);
            elseif ~state.bufferWarningShown
                warning('Force buffer is full; additional samples are not stored.');
                state.bufferWarningShown = true;
            end
        end

        if c.btnZero.Value
            state.zeroValues = state.lastRawSample;
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

        if state.nSamples > 0 && ...
                mod(state.nSamples, state.plotInterval) == 0
            target = str2double(c.forceTargetBox.String);
            if isnan(target)
                target = 100;
            end
            update_force_plot(c.ax, state.lines, state.forceData, ...
                forceCfg.forceFs, forceCfg.forceDisplayTimeSec, ...
                forceCfg.forceBufferTimeSec, target, state.nSamples);
            drawnow limitrate;
        end
    end

    function update_sign_label()
        currentSignState = state.controls.forceSignCheckbox.Value;
        if currentSignState == state.lastSignState
            return;
        end
        state.lastSignState = currentSignState;
        if currentSignState
            state.controls.forceSignLabel.String = sprintf('%s\n%s', ...
                '(+): Extension', '(-): Flexion ');
        else
            state.controls.forceSignLabel.String = sprintf('%s\n%s', ...
                '(+): Flexion', '(-): Extension ');
        end
    end

    function force_timer_error(~, event)
        warning('Force stream timer stopped: %s', event.Data.Message);
    end

end

function cfg = default_force_cfg()
cfg.forcePort = 'COM4';
cfg.forceFs = 50;
cfg.forceMaxDurationSec = 10 * 60;
cfg.forceDisplayTimeSec = 15;
cfg.forceBufferTimeSec = 5;
cfg.forcePlotRateHz = 10;
cfg.forceCalibrationFile = '';
cfg.forcePromptCalibration = true;
cfg.forceDefaultCalibrationFactors = [10 10 10];
cfg.forceDefaultZeroValues = [0 0 0];
cfg.forceDefaultReverseStates = [false false false];
end

function cfg = merge_force_cfg(cfg, userCfg)
names = fieldnames(cfg);
for i = 1:numel(names)
    if isfield(userCfg, names{i})
        cfg.(names{i}) = userCfg.(names{i});
    end
end
end

function state = initialize_force_state(cfg)
[calibrationFactors, zeroValues, reverseStates] = load_force_calibration(cfg);
[fig, controls] = setup_force_figure();

try
    serialObj = serial(cfg.forcePort, 'BaudRate', 115200, 'Terminator', 'LF');
    fopen(serialObj);
    pause(1);
    flushinput(serialObj);
catch ME
    if ishandle(fig)
        delete(fig);
    end
    rethrow(ME);
end

fprintf('Arduino force stream connected on %s\n', cfg.forcePort);
maxSamples = round(cfg.forceFs * cfg.forceMaxDurationSec);
state = struct();
state.fig = fig;
state.controls = controls;
state.serialObj = serialObj;
state.timer = [];
state.sessionClock = [];
state.calibrationFactors = reshape(calibrationFactors, 1, 3);
state.zeroValues = reshape(zeroValues, 1, 3);
state.reverseStates = logical(reshape(reverseStates, 1, 3));
state.forceData = zeros(maxSamples, 3);
state.arduinoTime = zeros(maxSamples, 1);
state.sessionTime = zeros(maxSamples, 1);
state.nSamples = 0;
state.lastRawSample = zeros(1, 3);
state.lastSignState = controls.forceSignCheckbox.Value;
state.plotInterval = max(1, round(cfg.forceFs / cfg.forcePlotRateHz));
state.lines = initialize_force_lines(controls.ax);
state.bufferWarningShown = false;
setappdata(fig, 'forceStopRequested', false);
end

function [factors, zeroValues, reverseStates] = load_force_calibration(cfg)
factors = cfg.forceDefaultCalibrationFactors;
zeroValues = cfg.forceDefaultZeroValues;
reverseStates = cfg.forceDefaultReverseStates;
calibrationFile = cfg.forceCalibrationFile;

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

data = load(calibrationFile, ...
    'calibrationFactors', 'zeroValues', 'reverseStates');
required = {'calibrationFactors', 'zeroValues', 'reverseStates'};
for i = 1:numel(required)
    if ~isfield(data, required{i})
        error('Calibration file is missing %s.', required{i});
    end
end
factors = data.calibrationFactors;
zeroValues = data.zeroValues;
reverseStates = data.reverseStates;
fprintf('Loaded force calibration: %s\n', calibrationFile);
end

function out = export_force_state(state, cfg)
n = state.nSamples;
out = struct();
out.data = state.forceData(1:n, :);
out.arduinoTime = state.arduinoTime(1:n);
out.sessionTime = state.sessionTime(1:n);
out.fs = cfg.forceFs;
out.calibrationFactors = state.calibrationFactors;
out.zeroValues = state.zeroValues;
out.reverseStates = state.reverseStates;
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
        fclose(serialObj);
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

function [fig, c] = setup_force_figure()
% Keep the force-stream layout identical to streamForceEMG.m.
fig = figure('Name', 'Force Recording - 3 Load Cells', ...
    'NumberTitle', 'off', 'Color', [0.94 0.94 0.94], ...
    'Position', [100 100 1200 700]);
c.ax = axes('Parent', fig, 'Units', 'normalized', ...
    'Position', [0.07 0.28 0.88 0.65]);
hold(c.ax, 'on'); grid(c.ax, 'on');
xlabel(c.ax, 'Time (s)');
ylabel(c.ax, 'Force (% calibrated)');
title(c.ax, 'Live Force Data');

c.btnClose = make_button(fig, 'Close', [0.88 0.04 0.08 0.05]);
c.btnZero = make_button(fig, 'Zero', [0.78 0.04 0.08 0.05]);
c.btnRecord = make_button(fig, 'Record', [0.68 0.04 0.08 0.05]);
c.btnRecordTracking = make_button(fig, 'Track Record', ...
    [0.55 0.04 0.11 0.05]);

c.participantIDBox = labelled_edit(fig, 'Participant', '', ...
    [0.04 0.17 0.08 0.03], [0.04 0.13 0.08 0.04]);
c.sessionBox = labelled_edit(fig, 'Session', '1', ...
    [0.14 0.17 0.06 0.03], [0.14 0.13 0.06 0.04]);
c.trialBox = labelled_edit(fig, 'Trial', '1', ...
    [0.22 0.17 0.06 0.03], [0.22 0.13 0.06 0.04]);

make_label(fig, 'Digit/Channel', [0.30 0.17 0.08 0.03]);
c.forceChanDropdown = uicontrol(fig, 'Style', 'popupmenu', ...
    'String', {'1','2','3'}, 'Units', 'normalized', ...
    'Position', [0.30 0.13 0.08 0.04]);
make_label(fig, 'Trace', [0.40 0.17 0.08 0.03]);
c.traceTypeDropdown = uicontrol(fig, 'Style', 'popupmenu', ...
    'String', {'Trapezium','Triangular'}, 'Units', 'normalized', ...
    'Position', [0.40 0.13 0.10 0.04]);

c.tWaitBox = labelled_edit(fig, 'Wait (s)', '5', ...
    [0.04 0.08 0.06 0.03], [0.04 0.04 0.06 0.04]);
c.tSlopeBox = labelled_edit(fig, 'Slope (s)', '3', ...
    [0.12 0.08 0.06 0.03], [0.12 0.04 0.06 0.04]);
c.tPlateauBox = labelled_edit(fig, 'Plateau (s)', '5', ...
    [0.20 0.08 0.07 0.03], [0.20 0.04 0.07 0.04]);
c.forceTargetBox = labelled_edit(fig, 'Target (%)', '30', ...
    [0.29 0.08 0.07 0.03], [0.29 0.04 0.07 0.04]);

c.forceSignLabel = uicontrol(fig, 'Style', 'text', ...
    'String', sprintf('%s\n%s', '(+): Flexion', '(-): Extension '), ...
    'Units', 'normalized', 'Position', [0.39 0.04 0.10 0.06], ...
    'BackgroundColor', fig.Color);
c.forceSignCheckbox = uicontrol(fig, 'Style', 'checkbox', ...
    'String', 'Extension +', 'Value', 0, 'Units', 'normalized', ...
    'Position', [0.39 0.105 0.10 0.035], ...
    'BackgroundColor', fig.Color);
end

function h = make_button(fig, label, pos)
h = uicontrol(fig, 'Style', 'togglebutton', 'String', label, ...
    'Units', 'normalized', 'Position', pos);
end

function h = labelled_edit(fig, label, value, labelPos, editPos)
make_label(fig, label, labelPos);
h = uicontrol(fig, 'Style', 'edit', 'String', value, ...
    'Units', 'normalized', 'Position', editPos);
end

function make_label(fig, label, pos)
uicontrol(fig, 'Style', 'text', 'String', label, ...
    'Units', 'normalized', 'Position', pos, ...
    'BackgroundColor', fig.Color);
end

function forceLines = initialize_force_lines(ax)
colors = lines(3);
forceLines = gobjects(3, 1);
for i = 1:3
    forceLines(i) = animatedline(ax, 'Color', colors(i,:), ...
        'LineWidth', 1.5);
end
legend(ax, {'Load cell 1','Load cell 2','Load cell 3'}, ...
    'Location', 'northwest');
end

function update_force_plot(ax, forceLines, forceData, fsForce, ...
        displayTime, bufferTime, forceTarget, currentIndex)
currentTime = currentIndex / fsForce;
idx = max(1, currentIndex - round(displayTime * fsForce)):currentIndex;
t = idx / fsForce;
for i = 1:3
    clearpoints(forceLines(i));
    addpoints(forceLines(i), t, forceData(idx, i));
end
xlim(ax, [currentTime - displayTime, currentTime + bufferTime]);
ylim(ax, [-10 max(forceTarget * 1.2, 20)]);
end
