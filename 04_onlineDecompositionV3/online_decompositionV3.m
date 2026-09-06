
function out = online_decompositionV3(signal,parameters,cfg)
% online_decompositionV3 online MU decomposition with live force.
%
%   out = onlineForceStreamV2(signal,parameters,cfg)
%


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

% Run V2 decomposition while the force timer reads Arduino samples.
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
            update_force_plot(c.ax, forceState.lines, forceState.forceData, ...
                forceCfg.forceFs, forceCfg.forceDisplayTimeSec, ...
                forceCfg.forceBufferTimeSec, target, forceState.nSamples);
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

try
    serialObj = serialport(cfg.forcePort, 115200, 'Timeout', 2);
    configureTerminator(serialObj, "LF");
    pause(1);
    flush(serialObj, "input");
catch ME
    % Delete a partially created connection so COM4 is free next time.
    if exist('serialObj', 'var') && ~isempty(serialObj)
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

fprintf('Arduino force stream connected on %s\n', cfg.forcePort);
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
forceState.lines = initialize_force_lines(controls.ax);
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
fig = figure('Name', 'Force and Real-Time Spike Trains', ...
    'NumberTitle', 'off', 'Color', [0.94 0.94 0.94], ...
    'Position', [60 50 1450 850]);
c.ax = axes('Parent', fig, 'Units', 'normalized', ...
    'Position', [0.05 0.56 0.75 0.39]);
hold(c.ax, 'on'); grid(c.ax, 'on');
xlabel(c.ax, 'Time (s)');
ylabel(c.ax, 'Force (% calibrated)');
title(c.ax, 'Live Force Data');
ylim(c.ax, [-10 110]);

c.axRaster = axes('Parent', fig, 'Units', 'normalized', ...
    'Position', [0.05 0.08 0.75 0.37]);
grid(c.axRaster, 'on');
title(c.axRaster, 'Live Spike Trains');
xlabel(c.axRaster, 'Time (s)');
ylabel(c.axRaster, 'Motor Unit');

panel = uipanel('Parent',fig,'Title','Force Controls', ...
    'Units','normalized','Position',[0.82 0.05 0.17 0.90], ...
    'BackgroundColor',fig.Color);
labelX = 0.06; fieldX = 0.52; labelW = 0.43; fieldW = 0.42;
rowY = [0.91 0.83 0.75 0.67 0.59 0.51 0.43 0.35 0.27];

c.participantIDBox = labelled_edit(panel, 'Participant', '', ...
    [labelX rowY(1) labelW 0.045], [fieldX rowY(1) fieldW 0.05]);
c.sessionBox = labelled_edit(panel, 'Session', '1', ...
    [labelX rowY(2) labelW 0.045], [fieldX rowY(2) fieldW 0.05]);
c.trialBox = labelled_edit(panel, 'Trial', '1', ...
    [labelX rowY(3) labelW 0.045], [fieldX rowY(3) fieldW 0.05]);

make_label(panel, 'Digit/Channel', [labelX rowY(4) labelW 0.045]);
c.forceChanDropdown = uicontrol(panel, 'Style', 'popupmenu', ...
    'String', {'1','2','3'}, 'Units', 'normalized', ...
    'Position', [fieldX rowY(4) fieldW 0.05]);
make_label(panel, 'Trace', [labelX rowY(5) labelW 0.045]);
c.traceTypeDropdown = uicontrol(panel, 'Style', 'popupmenu', ...
    'String', {'Trapezium','Triangular'}, 'Units', 'normalized', ...
    'Position', [fieldX rowY(5) fieldW 0.05]);

c.tWaitBox = labelled_edit(panel, 'Wait (s)', '5', ...
    [labelX rowY(6) labelW 0.045], [fieldX rowY(6) fieldW 0.05]);
c.tSlopeBox = labelled_edit(panel, 'Slope (s)', '3', ...
    [labelX rowY(7) labelW 0.045], [fieldX rowY(7) fieldW 0.05]);
c.tPlateauBox = labelled_edit(panel, 'Plateau (s)', '5', ...
    [labelX rowY(8) labelW 0.045], [fieldX rowY(8) fieldW 0.05]);
c.forceTargetBox = labelled_edit(panel, 'Target (%)', '30', ...
    [labelX rowY(9) labelW 0.045], [fieldX rowY(9) fieldW 0.05]);

c.forceSignCheckbox = uicontrol(panel, 'Style', 'checkbox', ...
    'String', 'Extension +', 'Value', 0, 'Units', 'normalized', ...
    'Position', [0.06 0.19 0.88 0.05], ...
    'BackgroundColor', panel.BackgroundColor);
c.forceSignLabel = uicontrol(panel, 'Style', 'text', ...
    'String', sprintf('%s\n%s', '(+): Flexion', '(-): Extension '), ...
    'Units', 'normalized', 'Position', [0.06 0.125 0.88 0.06], ...
    'HorizontalAlignment','left','BackgroundColor',panel.BackgroundColor);

c.btnRecordTracking = make_button(panel,'Track Record',[0.06 0.065 0.43 0.05]);
c.btnRecord = make_button(panel,'Record',[0.51 0.065 0.43 0.05]);
c.btnZero = make_button(panel,'Zero',[0.06 0.005 0.43 0.05]);
c.btnClose = make_button(panel,'Close',[0.51 0.005 0.43 0.05]);
c.btnClose.BackgroundColor = [0.85 0.25 0.25];
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

function make_label(parent, label, pos)
uicontrol(parent, 'Style', 'text', 'String', label, ...
    'Units', 'normalized', 'Position', pos, ...
    'HorizontalAlignment','left', ...
    'BackgroundColor', get(parent,'BackgroundColor'));
end


%% Init 3 channel 
function forceLines = initialize_force_lines(ax)
colors = lines(3);
forceLines = gobjects(3, 1);
for i = 1:3
    forceLines(i) = animatedline(ax, 'Color', colors(i,:), ...
        'LineWidth', 1.5);
end
legend(ax, {'Thumb','Index finger','Middle finger'}, ...
    'Location', 'northwest');
end


%% Helper to refresh force plot

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
ylim(ax, [-10 110]);
end
