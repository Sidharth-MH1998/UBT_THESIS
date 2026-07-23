function session = run_novecento_force_one_session()
%RUN_NOVECENTO_FORCE_ONE_SESSION Acquire Novecento EMG and Arduino force.
%
% This is a separate combined application. It does not modify or execute
% the blocking loops in novecento_live_plot.m or MyForceStream.m.
%
% Controls:
%   r          Mark the synchronized EMG/force recording start
%   q          Mark the synchronized stop and create recordedEMG/recordedForce
%   Zero Force Set the current force values as zero
%   Stop       Stop both streams and close both hardware connections safely

projectDir = fileparts(mfilename('fullpath'));
testStreamDir = fullfile(projectDir, 'test_stream');
forceDir = fullfile(projectDir, 'force');
addpath(testStreamDir);

cfg = make_novecento_config();
forceCfg = make_force_config(forceDir);

fprintf('\n=== Combined Novecento EMG + Arduino force ===\n');
fprintf('Connecting to Arduino on %s...\n', forceCfg.port);
serialObj = serialport(forceCfg.port, forceCfg.baudRate, 'Timeout', 2);
serialCleanup = onCleanup(@() cleanup_serial(serialObj));
configureTerminator(serialObj, 'LF');
flush(serialObj);

fprintf('Connecting to Novecento...\n');
dev = novecento_connect(cfg);
novecentoCleanup = onCleanup(@() cleanup_novecento(dev));

[fsEmg, samplesPerBlock] = validate_novecento_settings(dev, cfg);
[calibrationFactors, zeroValues, reverseStates] = load_force_calibration(forceCfg);

[emgFig, emgAx, emgStatus] = make_emg_figure();
[forceFig, forceAx, forceLines, zeroButton, stopButton, forceStatus] = ...
    make_force_figure(forceCfg.numChannels);

state = struct();
state.emgData = [];
state.forceData = zeros(forceCfg.maxSamples, forceCfg.numChannels);
state.forceArduinoTimeMs = nan(forceCfg.maxSamples, 1);
state.forceHostTimeSec = nan(forceCfg.maxSamples, 1);
state.forceCount = 0;
state.lastFilteredForce = [];
state.lastRawForce = zeros(1, forceCfg.numChannels);
state.recordStartEmg = [];
state.recordEndEmg = [];
state.recordStartForce = [];
state.recordEndForce = [];
state.recordedEMG = [];
state.recordedForce = [];
state.recordState = 'Idle';
state.stopRequested = false;
state.zeroRequested = false;
state.calibrationFactors = calibrationFactors;
state.zeroValues = zeroValues;
state.reverseStates = reverseStates;
state.fsEmg = fsEmg;
state.fsForce = forceCfg.fs;

setappdata(emgFig, 'combinedState', state);
setappdata(forceFig, 'combinedState', state);
set(emgFig, 'WindowKeyPressFcn', @marker_keypress);
set(forceFig, 'WindowKeyPressFcn', @marker_keypress);
set(zeroButton, 'Callback', @request_zero);
set(stopButton, 'Callback', @request_stop);
set(emgFig, 'CloseRequestFcn', @request_stop);
set(forceFig, 'CloseRequestFcn', @request_stop);

assign_outputs(state);
streamStart = tic;

fprintf('Both streams are running in this MATLAB session.\n');
fprintf('Press r to start and q to stop a synchronized recording.\n\n');

while isgraphics(emgFig) && isgraphics(forceFig)
    state = getappdata(emgFig, 'combinedState');
    if state.stopRequested
        break;
    end

    % This call waits for one complete Novecento block. The Arduino keeps
    % sending during that interval; all complete queued lines are drained
    % immediately afterward.
    rawAll = novecento_read_emg_block(dev, cfg.activeInputs, samplesPerBlock);
    state.emgData = [state.emgData double(rawAll(cfg.emgChannels, :))];

    state = drain_force_lines(serialObj, state, forceCfg, toc(streamStart));

    if state.zeroRequested
        state.zeroValues = state.lastRawForce;
        state.lastFilteredForce = [];
        state.zeroRequested = false;
        fprintf('Force channels zeroed at Arduino values: [%g %g %g]\n', ...
            state.zeroValues);
    end

    update_emg_plot(emgAx, emgStatus, state, cfg);
    update_force_plot(forceAx, forceLines, forceStatus, state, forceCfg);

    setappdata(emgFig, 'combinedState', state);
    setappdata(forceFig, 'combinedState', state);
    assign_outputs(state);
    drawnow limitrate;
end

state = get_latest_state(emgFig, forceFig, state);
session = trim_session_output(state);
assign_outputs(state);

if isgraphics(emgFig)
    set(emgFig, 'CloseRequestFcn', '');
    delete(emgFig);
end
if isgraphics(forceFig)
    set(forceFig, 'CloseRequestFcn', '');
    delete(forceFig);
end

fprintf('Combined streaming stopped safely.\n');
end

function cleanup_serial(serialObj)
if isempty(serialObj)
    return;
end
try
    flush(serialObj);
catch
end
try
    delete(serialObj);
catch
end
end

function cleanup_novecento(dev)
if isempty(dev)
    return;
end
try
    novecento_disconnect(dev);
catch cleanupError
    warning('CombinedAcquisition:NovecentoCleanup', '%s', cleanupError.message);
end
end

function cfg = make_novecento_config()
cfg = struct();
cfg.socketTimeoutSec = 100;
cfg.activeInputs = [1 2];
cfg.emgChannels = [1:64 71:134];
cfg.previewChannels = 1:8:128;
cfg.blockDurationSec = 1;
cfg.visibleWindowSec = 15;
cfg.GainFactor = 0.2861;
cfg.FSelAux = 2;
cfg.forceInputChannelCounts = [];
cfg.hardwareQueryRetries = 3;
cfg.hardwareQueryPauseSec = 0.2;
cfg.AnOutINSource = 0;
cfg.AnOutChan = 1;
cfg.AnOutGain = bin2dec('00000000');
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
cfg.FsampCode(cfg.activeInputs) = 1;
end

function forceCfg = make_force_config(forceDir)
forceCfg.port = "COM4";
forceCfg.baudRate = 115200;
forceCfg.fs = 50;
forceCfg.numChannels = 3;
forceCfg.maxDurationSec = 10 * 60;
forceCfg.maxSamples = forceCfg.fs * forceCfg.maxDurationSec;
forceCfg.visibleWindowSec = 15;
forceCfg.plotUpdateRate = 10;
forceCfg.spikeThreshold = 20;
forceCfg.smoothingAlpha = 0.3;
forceCfg.calibrationFile = fullfile(forceDir, 'calibrationData.mat');
end

function [fs, samplesPerBlock] = validate_novecento_settings(dev, cfg)
fsValues = dev.fsInput(cfg.activeInputs);
if any(fsValues <= 0) || numel(unique(fsValues)) ~= 1
    error('All active Novecento inputs must have one valid sampling rate.');
end
fs = fsValues(1);
samplesPerBlock = fs * cfg.blockDurationSec;
if mod(samplesPerBlock, 1) ~= 0
    error('Novecento block duration must produce an integer sample count.');
end
samplesPerBlock = round(samplesPerBlock);
totalChannels = sum(dev.NumChan(cfg.activeInputs));
if max(cfg.emgChannels) > totalChannels
    error('cfg.emgChannels exceeds the %d available active channels.', totalChannels);
end
end

function [factors, zerosAtRest, reversed] = load_force_calibration(forceCfg)
factors = [10 10 10];
zerosAtRest = [0 0 0];
reversed = [false false false];
if isfile(forceCfg.calibrationFile)
    saved = load(forceCfg.calibrationFile);
    if isfield(saved, 'calibrationFactors')
        factors = saved.calibrationFactors;
    end
    if isfield(saved, 'zeroValues')
        zerosAtRest = saved.zeroValues;
    end
    if isfield(saved, 'reverseStates')
        reversed = saved.reverseStates;
    end
end
factors = reshape(factors(1:forceCfg.numChannels), 1, []);
zerosAtRest = reshape(zerosAtRest(1:forceCfg.numChannels), 1, []);
reversed = logical(reshape(reversed(1:forceCfg.numChannels), 1, []));
if any(factors == 0)
    error('Force calibration factors must be nonzero.');
end
end

function [fig, ax, status] = make_emg_figure()
fig = figure('Name', 'Combined acquisition - Novecento EMG', ...
    'NumberTitle', 'off', 'Color', 'w', 'Position', [30 80 1150 650]);
ax = axes('Parent', fig, 'Position', [0.07 0.12 0.89 0.79]);
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Channel');
title(ax, 'Live Novecento EMG');
status = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.03 0.94 0.94 0.04], 'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w', 'String', 'Connecting...');
end

function [fig, ax, linesOut, zeroButton, stopButton, status] = make_force_figure(nChannels)
fig = figure('Name', 'Combined acquisition - Arduino force', ...
    'NumberTitle', 'off', 'Color', 'w', 'Position', [120 120 1050 600]);
ax = axes('Parent', fig, 'Position', [0.08 0.18 0.88 0.72]);
hold(ax, 'on');
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Force (% calibrated)');
title(ax, 'Live Force');
colors = lines(nChannels);
linesOut = gobjects(nChannels, 1);
for channel = 1:nChannels
    linesOut(channel) = animatedline(ax, 'Color', colors(channel, :), ...
        'LineWidth', 1.5);
end
legend(ax, compose('Load cell %d', 1:nChannels), 'Location', 'northwest');
zeroButton = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Zero Force', ...
    'Units', 'normalized', 'Position', [0.72 0.04 0.11 0.07]);
stopButton = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Stop Both', ...
    'Units', 'normalized', 'Position', [0.85 0.04 0.11 0.07]);
status = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.04 0.04 0.64 0.07], 'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w', 'String', 'Waiting for force samples...');
end

function state = drain_force_lines(serialObj, state, forceCfg, hostTimeSec)
while serialObj.NumBytesAvailable > 0 && state.forceCount < forceCfg.maxSamples
    try
        textLine = readline(serialObj);
    catch readError
        warning('CombinedAcquisition:ForceSerialRead', '%s', readError.message);
        break;
    end
    values = sscanf(char(textLine), '%f,%f,%f,%f');
    if numel(values) < forceCfg.numChannels + 1
        continue;
    end

    rawForce = reshape(values(2:forceCfg.numChannels + 1), 1, []);
    rawForce(state.reverseStates) = -rawForce(state.reverseStates);
    state.lastRawForce = rawForce;
    calibrated = (rawForce - state.zeroValues) ./ state.calibrationFactors * 100;

    % Preserve the force-processing logic used by MyForceStream: reject a
    % change larger than 20 calibrated units, then apply alpha=0.3 EMA.
    if isempty(state.lastFilteredForce)
        filtered = calibrated;
    else
        filtered = calibrated;
        spikeMask = abs(calibrated - state.lastFilteredForce) > forceCfg.spikeThreshold;
        filtered(spikeMask) = state.lastFilteredForce(spikeMask);
        filtered = forceCfg.smoothingAlpha * filtered + ...
            (1 - forceCfg.smoothingAlpha) * state.lastFilteredForce;
    end

    state.forceCount = state.forceCount + 1;
    state.forceData(state.forceCount, :) = filtered;
    state.forceArduinoTimeMs(state.forceCount) = values(1);
    state.forceHostTimeSec(state.forceCount) = hostTimeSec;
    state.lastFilteredForce = filtered;
end
end

function update_emg_plot(ax, status, state, cfg)
if isempty(state.emgData) || ~isgraphics(ax)
    return;
end
previewRows = cfg.previewChannels;
previewRows = previewRows(previewRows >= 1 & previewRows <= size(state.emgData, 1));
nVisible = min(size(state.emgData, 2), round(cfg.visibleWindowSec * state.fsEmg));
firstSample = size(state.emgData, 2) - nVisible + 1;
novecento_plot_stacked(ax, state.emgData(previewRows, end-nVisible+1:end), ...
    cfg.emgChannels(previewRows), state.fsEmg, firstSample, cfg.visibleWindowSec);
title(ax, sprintf('Live Novecento EMG | %d channels shown', numel(previewRows)));
set(status, 'String', sprintf('EMG: %.1f s | Force samples: %d | Marker: %s', ...
    size(state.emgData, 2) / state.fsEmg, state.forceCount, state.recordState));
end

function update_force_plot(ax, forceLines, status, state, forceCfg)
if state.forceCount < 1 || ~isgraphics(ax)
    return;
end
count = state.forceCount;
startIndex = max(1, count - round(forceCfg.visibleWindowSec * forceCfg.fs) + 1);
indices = startIndex:count;
t = (indices - 1) / forceCfg.fs;
for channel = 1:forceCfg.numChannels
    clearpoints(forceLines(channel));
    addpoints(forceLines(channel), t, state.forceData(indices, channel));
end
xlim(ax, [max(0, t(end) - forceCfg.visibleWindowSec), max(forceCfg.visibleWindowSec, t(end))]);
visibleValues = state.forceData(indices, :);
limits = [min(visibleValues, [], 'all') max(visibleValues, [], 'all')];
if all(isfinite(limits))
    span = max(10, diff(limits));
    ylim(ax, [limits(1)-0.1*span limits(2)+0.1*span]);
end
set(status, 'String', sprintf('Force: %d samples (%.1f s) | Marker: %s', ...
    count, count / forceCfg.fs, state.recordState));
end

function marker_keypress(source, event)
figures = findall(groot, 'Type', 'figure');
state = getappdata(source, 'combinedState');
if isempty(state)
    return;
end
switch lower(event.Key)
    case 'r'
        state.recordStartEmg = size(state.emgData, 2) + 1;
        state.recordStartForce = state.forceCount + 1;
        state.recordEndEmg = [];
        state.recordEndForce = [];
        state.recordedEMG = [];
        state.recordedForce = [];
        state.recordState = sprintf('START: EMG %d, force %d', ...
            state.recordStartEmg, state.recordStartForce);
    case 'q'
        if isempty(state.recordStartEmg)
            state.recordState = 'Press r before q';
        else
            state.recordEndEmg = size(state.emgData, 2);
            state.recordEndForce = state.forceCount;
            if state.recordEndEmg >= state.recordStartEmg
                state.recordedEMG = state.emgData(:, state.recordStartEmg:state.recordEndEmg);
            end
            if state.recordEndForce >= state.recordStartForce
                state.recordedForce = state.forceData( ...
                    state.recordStartForce:state.recordEndForce, :);
            end
            state.recordState = sprintf('STOP: EMG %d, force %d', ...
                state.recordEndEmg, state.recordEndForce);
        end
    otherwise
        return;
end
for index = 1:numel(figures)
    if isappdata(figures(index), 'combinedState')
        setappdata(figures(index), 'combinedState', state);
    end
end
assign_outputs(state);
end

function request_zero(source, ~)
fig = ancestor(source, 'figure');
state = getappdata(fig, 'combinedState');
state.zeroRequested = true;
setappdata(fig, 'combinedState', state);
copy_state_to_other_figure(fig, state);
end

function request_stop(source, ~)
if strcmp(get(source, 'Type'), 'figure')
    fig = source;
else
    fig = ancestor(source, 'figure');
end
state = getappdata(fig, 'combinedState');
if isempty(state)
    delete(fig);
    return;
end
state.stopRequested = true;
setappdata(fig, 'combinedState', state);
copy_state_to_other_figure(fig, state);
end

function copy_state_to_other_figure(sourceFig, state)
figures = findall(groot, 'Type', 'figure');
for index = 1:numel(figures)
    if figures(index) ~= sourceFig && isappdata(figures(index), 'combinedState')
        setappdata(figures(index), 'combinedState', state);
    end
end
end

function state = get_latest_state(emgFig, forceFig, fallback)
state = fallback;
if isgraphics(emgFig) && isappdata(emgFig, 'combinedState')
    state = getappdata(emgFig, 'combinedState');
elseif isgraphics(forceFig) && isappdata(forceFig, 'combinedState')
    state = getappdata(forceFig, 'combinedState');
end
end

function output = trim_session_output(state)
output = state;
output.forceData = state.forceData(1:state.forceCount, :);
output.forceArduinoTimeMs = state.forceArduinoTimeMs(1:state.forceCount);
output.forceHostTimeSec = state.forceHostTimeSec(1:state.forceCount);
end

function assign_outputs(state)
assignin('base', 'emgData', state.emgData);
assignin('base', 'forceData', state.forceData(1:state.forceCount, :));
assignin('base', 'forceArduinoTimeMs', state.forceArduinoTimeMs(1:state.forceCount));
assignin('base', 'recordStartSample', state.recordStartEmg);
assignin('base', 'recordEndSample', state.recordEndEmg);
assignin('base', 'recordStartForce', state.recordStartForce);
assignin('base', 'recordEndForce', state.recordEndForce);
assignin('base', 'recordedEMG', state.recordedEMG);
assignin('base', 'recordedForce', state.recordedForce);
assignin('base', 'fs', state.fsEmg);
assignin('base', 'fs_force', state.fsForce);
end
