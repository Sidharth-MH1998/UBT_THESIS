clc
close all
clear all

% Force-only recording script for 3 load cells.
% This keeps the same main-loop structure, calibration, zeroing, spike
% replacement, exponential smoothing, target tracking, and saving behavior.

%% Parameters
ard_port = 'COM4';                 % Modify based on the system
fs_force = 50;                     % Force sampling frequency (50 Hz)
maxDuration = 10 * 60;             % Maximum recording time (10 minutes)

numForceChan = 3;                  % Number of force channels
displayTime = 15;                  % Visible plot time plus buffer
bufferTime = 5;                    % Extra buffer time for target plotting
plotUpdateRate = 10;               % Plot refresh rate (Hz); data is still recorded at 50 Hz
plotUpdateInterval = round(fs_force / plotUpdateRate);

% Preallocate size for 10 minutes worth of data
maxForceSamples = fs_force * maxDuration;
forceData = zeros(maxForceSamples, numForceChan);
currentForceIndex = 0;

% Initialize default calibration values
defaultCalibrationFactors = [10, 10, 10];
defaultZeroValues = [0, 0, 0];
defaultReverseStates = [false, false, false];

% Select a calibration file. Press Cancel to use the default values.
forceScriptDir = fileparts(mfilename('fullpath'));
[calibrationFileName, calibrationFolder] = uigetfile( ...
    fullfile(forceScriptDir, '*.mat'), ...
    'Select calibration file, or press Cancel to use defaults');

if ~isequal(calibrationFileName, 0)
    calibrationFile = fullfile(calibrationFolder, calibrationFileName);
    calibrationData = load(calibrationFile, ...
        'calibrationFactors', 'zeroValues', 'reverseStates');
    calibrationFactors = calibrationData.calibrationFactors;
    zeroValues = calibrationData.zeroValues;
    reverseStates = calibrationData.reverseStates;
    disp(['Loaded calibration: ', calibrationFile]);
else
    calibrationFactors = defaultCalibrationFactors;
    zeroValues = defaultZeroValues;
    reverseStates = defaultReverseStates;
    disp('No calibration file selected. Using default calibration values.');
end

% Initialize figure and axes
[fig, ax_f, btnClose, btnZero, btnRecord, btnRecordTracking, ...
    forceChanDropdown, traceTypeDropdown, tWaitBox, tSlopeBox, tPlateauBox, ...
    forceTargetBox, forceSignLabel, forceSignCheckbox, participantIDBox, ...
    trialBox, sessionBox] = setupForceOnlyFigure();

%% Setup Force streaming from Arduino
serialObj = initializeArduinoStream(ard_port);

%% Initialize variables
forceTarget = 100;
forceMin = 0;
forceSample = [0; 0; 0];
tStamps = zeros(1, maxForceSamples);
lastForceSignState = forceSignCheckbox.Value;
recording = false;
recordingTracking = false;
recordStartForce = [];
recordEndForce = [];
zeroed = false;

elapsedExecTimes = zeros(1, maxForceSamples);
forceTimes = zeros(1, maxForceSamples);

forceLines = initializeForcePlot(ax_f, numForceChan);

%% Main loop to stream force data at 50 Hz for plotting
forceStreamTime = tic;

while ishandle(fig)
    loopStartTime = tic;
    try
        % ----------- Force data streaming -----------
        if serialObj.BytesAvailable > 0
            % Expected Arduino line format:
            % timestamp,force1,force2,force3
            fSample = fscanf(serialObj, '%f,%f,%f,%f');

            if numel(fSample) >= 4
                nextForceIndex = currentForceIndex + 1;
                if nextForceIndex > maxForceSamples
                    nextForceIndex = 1;
                end

                tStamps(nextForceIndex) = fSample(1);
                forceSample = fSample(2:4);

                % Step 1: Apply channel reverse states
                for i = 1:numForceChan
                    if reverseStates(i)
                        forceSample(i) = -forceSample(i);
                    end
                end

                if forceSignCheckbox.Value ~= lastForceSignState
                    lastForceSignState = forceSignCheckbox.Value;
                    if lastForceSignState == 1
                        set(forceSignLabel, 'String', sprintf('%s\n%s', '(+): Extension', '(-): Flexion '));
                    else
                        set(forceSignLabel, 'String', sprintf('%s\n%s', '(+): Flexion', '(-): Extension '));
                    end
                end

                if forceSignCheckbox.Value == 1
                    forceSample = -forceSample;
                end

                % Step 2: Apply zero values and calibration factors
                calibratedForce = (forceSample(1:numForceChan)' - zeroValues(1:numForceChan)) ...
                    ./ calibrationFactors(1:numForceChan) * 100;

                % Step 3: Store calibrated force data
                currentForceIndex = nextForceIndex;
                forceData(currentForceIndex, :) = calibratedForce;

                % Step 4a: Detect and replace spikes
                spikeThreshold = 20;
                if currentForceIndex > 1
                    deltaForce = abs(calibratedForce - forceData(currentForceIndex - 1, :));
                    isSpike = deltaForce > spikeThreshold;
                    filteredForce = calibratedForce;
                    filteredForce(isSpike) = forceData(currentForceIndex - 1, isSpike);
                else
                    filteredForce = calibratedForce;
                end

                % Step 4b: Apply exponential moving average for smoothing
                alpha = 0.3;
                if currentForceIndex > 1
                    filteredForce = alpha * filteredForce + (1 - alpha) * forceData(currentForceIndex - 1, :);
                end

                % Store filtered data
                forceData(currentForceIndex, :) = filteredForce;

                % Step 6: Update plot
                if mod(currentForceIndex, plotUpdateInterval) == 0
                    updateForcePlot(ax_f, forceLines, forceData, fs_force, numForceChan, ...
                        displayTime, bufferTime, forceTarget, forceMin, currentForceIndex);
                end
                forceTimes(currentForceIndex) = toc(forceStreamTime);
            end
        else
            pause(0.0001);
        end

        % Handle zeroing
        if btnZero.Value
            zeroValues = forceSample(1:numForceChan)';
            btnZero.Value = false;
            zeroed = true;
            disp('Force channels zeroed.');
        end

        % Handle force tracking recording
        if btnRecordTracking.Value && ~recordingTracking
            ax_f.Color = [0.9, 1, 0.9];

            recordStartForce = currentForceIndex + 1;

            tWait = str2double(tWaitBox.String);
            tSlope = str2double(tSlopeBox.String);
            tPlateau = str2double(tPlateauBox.String);
            forceTarget = str2double(forceTargetBox.String);

            traceType = traceTypeDropdown.String{traceTypeDropdown.Value};

            if strcmp(traceType, 'Trapezium')
                [tTrace, fTrace] = force_trace_trapezium(tPlateau, tSlope, tWait, forceTarget, fs_force);
            elseif strcmp(traceType, 'Triangular')
                [tTrace, fTrace] = force_trace_triang(fs_force);
                forceTarget = 30;
                forceMin = -30;
            end

            currentTime = currentForceIndex / fs_force;
            tTrace = tTrace + currentTime;

            if strcmp(traceType, 'Trapezium')
                traceDuration = 2 * tWait + 2 * tSlope + tPlateau;
            elseif strcmp(traceType, 'Triangular')
                traceDuration = 25;
            end

            recordingTracking = true;
            traceStartTime = currentTime;

            forceTraceLine = animatedline(ax_f, 'Color', 'k', 'LineWidth', 1, 'LineStyle', '-', 'DisplayName','reference');
            lastPlottedIdx = 1;
        end

        % Update target trace if tracking is active
        if recordingTracking
            currentTime = currentForceIndex / fs_force;

            if currentTime <= (traceStartTime + traceDuration)
                validIdx = find(tTrace <= currentTime + bufferTime, 1, 'last');

                if ~isempty(validIdx) && validIdx > lastPlottedIdx
                    addpoints(forceTraceLine, tTrace(lastPlottedIdx:validIdx), fTrace(lastPlottedIdx:validIdx));
                    lastPlottedIdx = validIdx;
                end

                xlim(ax_f, [currentTime - displayTime, currentTime + bufferTime]);
            else
                recordingTracking = false;
                btnRecordTracking.Value = false;

                recordEndForce = currentForceIndex - 1;

                participantID = participantIDBox.String;
                trial = str2double(trialBox.String);
                session = str2double(sessionBox.String);

                forceTarget = str2double(forceTargetBox.String);
                digit = forceChanDropdown.Value;

                if isempty(participantID)
                    disp('Error: Participant ID is required.');
                elseif isnan(trial) || isnan(session)
                    disp('Error: Trial and Session must be integer values.');
                else
                    filename = sprintf('S%s_ss%d_dig%d_f%d_t%d.mat', ...
                        participantID, session, digit, forceTarget, trial);

                    recordedForce = cropCircularForceData(forceData, recordStartForce, recordEndForce, maxForceSamples);
                    save(filename, 'forceData', 'recordedForce', 'recordStartForce', 'recordEndForce', ...
                        'fs_force', 'calibrationFactors', 'zeroValues', 'reverseStates', 'tStamps');

                    disp(['Recording saved as: ', filename]);
                end

                forceTarget = 100;
                forceMin = 0;
                ax_f.Color = [1, 1, 1];
            end
        end

        % Handle manual recording
        if btnRecord.Value && ~recording
            recording = true;
            recordStartForce = currentForceIndex;
            ax_f.Color = [1, 0.95, 0.9];
            disp('Manual recording started.');
        elseif ~btnRecord.Value && recording
            recording = false;
            recordEndForce = currentForceIndex;
            ax_f.Color = [1, 1, 1];

            participantID = participantIDBox.String;
            trial = str2double(trialBox.String);
            session = str2double(sessionBox.String);
            forceTarget = str2double(forceTargetBox.String);

            if isempty(participantID)
                disp('Error: Participant ID is required.');
            elseif isnan(trial) || isnan(session)
                disp('Error: Trial and Session must be integer values.');
            else
                filename = sprintf('S%s_ss%d_f%d_t%d.mat', participantID, session, forceTarget, trial);

                recordedForce = cropCircularForceData(forceData, recordStartForce, recordEndForce, maxForceSamples);
                save(filename, 'forceData', 'recordedForce', 'recordStartForce', 'recordEndForce', ...
                    'fs_force', 'calibrationFactors', 'zeroValues', 'reverseStates', 'tStamps');

                disp(['Recording saved as: ', filename]);
            end
        end

        % Check if the close button is pressed
        if btnClose.Value
            closeSerialObject(serialObj);
            break;
        end

    catch ME
        disp(['Error occurred: ', ME.message]);
    end

    drawnow limitrate;
    if currentForceIndex > 0
        elapsedExecTimes(currentForceIndex) = toc(loopStartTime);
    end
end

% If the figure was closed without cleaning resources
if ~ishandle(fig)
    closeSerialObject(serialObj);
end

%% Local functions

function [fig, ax_f, btnClose, btnZero, btnRecord, btnRecordTracking, ...
    forceChanDropdown, traceTypeDropdown, tWaitBox, tSlopeBox, tPlateauBox, ...
    forceTargetBox, forceSignLabel, forceSignCheckbox, participantIDBox, ...
    trialBox, sessionBox] = setupForceOnlyFigure()

    fig = figure('Name', 'Force Recording - 3 Load Cells', ...
        'NumberTitle', 'off', ...
        'Color', [0.94, 0.94, 0.94], ...
        'Position', [100, 100, 1200, 700]);

    ax_f = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.07, 0.28, 0.88, 0.65]);
    hold(ax_f, 'on');
    grid(ax_f, 'on');
    xlabel(ax_f, 'Time (s)');
    ylabel(ax_f, 'Force (% calibrated)');
    title(ax_f, 'Live Force Data');

    btnClose = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Close', ...
        'Units', 'normalized', 'Position', [0.88, 0.04, 0.08, 0.05]);

    btnZero = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Zero', ...
        'Units', 'normalized', 'Position', [0.78, 0.04, 0.08, 0.05]);

    btnRecord = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Record', ...
        'Units', 'normalized', 'Position', [0.68, 0.04, 0.08, 0.05]);

    btnRecordTracking = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Track Record', ...
        'Units', 'normalized', 'Position', [0.55, 0.04, 0.11, 0.05]);

    uicontrol(fig, 'Style', 'text', 'String', 'Participant', ...
        'Units', 'normalized', 'Position', [0.04, 0.17, 0.08, 0.03], ...
        'BackgroundColor', fig.Color);
    participantIDBox = uicontrol(fig, 'Style', 'edit', 'String', '', ...
        'Units', 'normalized', 'Position', [0.04, 0.13, 0.08, 0.04]);

    uicontrol(fig, 'Style', 'text', 'String', 'Session', ...
        'Units', 'normalized', 'Position', [0.14, 0.17, 0.06, 0.03], ...
        'BackgroundColor', fig.Color);
    sessionBox = uicontrol(fig, 'Style', 'edit', 'String', '1', ...
        'Units', 'normalized', 'Position', [0.14, 0.13, 0.06, 0.04]);

    uicontrol(fig, 'Style', 'text', 'String', 'Trial', ...
        'Units', 'normalized', 'Position', [0.22, 0.17, 0.06, 0.03], ...
        'BackgroundColor', fig.Color);
    trialBox = uicontrol(fig, 'Style', 'edit', 'String', '1', ...
        'Units', 'normalized', 'Position', [0.22, 0.13, 0.06, 0.04]);

    uicontrol(fig, 'Style', 'text', 'String', 'Digit/Channel', ...
        'Units', 'normalized', 'Position', [0.30, 0.17, 0.08, 0.03], ...
        'BackgroundColor', fig.Color);
    forceChanDropdown = uicontrol(fig, 'Style', 'popupmenu', ...
        'String', {'1', '2', '3'}, ...
        'Units', 'normalized', 'Position', [0.30, 0.13, 0.08, 0.04]);

    uicontrol(fig, 'Style', 'text', 'String', 'Trace', ...
        'Units', 'normalized', 'Position', [0.40, 0.17, 0.08, 0.03], ...
        'BackgroundColor', fig.Color);
    traceTypeDropdown = uicontrol(fig, 'Style', 'popupmenu', ...
        'String', {'Trapezium', 'Triangular'}, ...
        'Units', 'normalized', 'Position', [0.40, 0.13, 0.10, 0.04]);

    uicontrol(fig, 'Style', 'text', 'String', 'Wait (s)', ...
        'Units', 'normalized', 'Position', [0.04, 0.08, 0.06, 0.03], ...
        'BackgroundColor', fig.Color);
    tWaitBox = uicontrol(fig, 'Style', 'edit', 'String', '5', ...
        'Units', 'normalized', 'Position', [0.04, 0.04, 0.06, 0.04]);

    uicontrol(fig, 'Style', 'text', 'String', 'Slope (s)', ...
        'Units', 'normalized', 'Position', [0.12, 0.08, 0.06, 0.03], ...
        'BackgroundColor', fig.Color);
    tSlopeBox = uicontrol(fig, 'Style', 'edit', 'String', '3', ...
        'Units', 'normalized', 'Position', [0.12, 0.04, 0.06, 0.04]);

    uicontrol(fig, 'Style', 'text', 'String', 'Plateau (s)', ...
        'Units', 'normalized', 'Position', [0.20, 0.08, 0.07, 0.03], ...
        'BackgroundColor', fig.Color);
    tPlateauBox = uicontrol(fig, 'Style', 'edit', 'String', '5', ...
        'Units', 'normalized', 'Position', [0.20, 0.04, 0.07, 0.04]);

    uicontrol(fig, 'Style', 'text', 'String', 'Target (%)', ...
        'Units', 'normalized', 'Position', [0.29, 0.08, 0.07, 0.03], ...
        'BackgroundColor', fig.Color);
    forceTargetBox = uicontrol(fig, 'Style', 'edit', 'String', '30', ...
        'Units', 'normalized', 'Position', [0.29, 0.04, 0.07, 0.04]);

    forceSignLabel = uicontrol(fig, 'Style', 'text', ...
        'String', sprintf('%s\n%s', '(+): Flexion', '(-): Extension '), ...
        'Units', 'normalized', 'Position', [0.39, 0.04, 0.10, 0.06], ...
        'BackgroundColor', fig.Color);

    forceSignCheckbox = uicontrol(fig, 'Style', 'checkbox', 'String', 'Extension +', ...
        'Value', 0, 'Units', 'normalized', 'Position', [0.39, 0.105, 0.10, 0.035], ...
        'BackgroundColor', fig.Color);
end

function serialObj = initializeArduinoStream(ard_port)
    serialObj = serial(ard_port, 'BaudRate', 115200, 'Terminator', 'LF');
    fopen(serialObj);
    pause(1);
    flushinput(serialObj);
    disp(['Arduino force stream connected on ', ard_port]);
end

function forceLines = initializeForcePlot(ax_f, numForceChan)
    colors = lines(numForceChan);
    forceLines = gobjects(numForceChan, 1);

    for i = 1:numForceChan
        forceLines(i) = animatedline(ax_f, 'Color', colors(i, :), 'LineWidth', 1.5);
    end

    legend(ax_f, {'Thumb', 'Index finger', 'Middle finger'}, 'Location', 'northwest');
end

function updateForcePlot(ax_f, forceLines, forceData, fs_force, numForceChan, ...
    displayTime, bufferTime, forceTarget, forceMin, currentForceIndex)

    if currentForceIndex < 1
        return
    end

    currentTime = currentForceIndex / fs_force;
    idxStart = max(1, currentForceIndex - round(displayTime * fs_force));
    idx = idxStart:currentForceIndex;
    t = idx / fs_force;

    for i = 1:numForceChan
        clearpoints(forceLines(i));
        addpoints(forceLines(i), t, forceData(idx, i));
    end

    xlim(ax_f, [currentTime - displayTime, currentTime + bufferTime]);
    yMax = max(forceTarget * 1.2, 20);
    yMin = min(forceMin * 1.2, -10);
    ylim(ax_f, [yMin, yMax]);
end

function [tTrace, fTrace] = force_trace_trapezium(tPlateau, tSlope, tWait, forceTarget, fs_force)
    tTotal = 2 * tWait + 2 * tSlope + tPlateau;
    tTrace = 0:1/fs_force:tTotal;
    fTrace = zeros(size(tTrace));

    rampUpStart = tWait;
    plateauStart = rampUpStart + tSlope;
    rampDownStart = plateauStart + tPlateau;
    rampDownEnd = rampDownStart + tSlope;

    rampUpIdx = tTrace >= rampUpStart & tTrace < plateauStart;
    plateauIdx = tTrace >= plateauStart & tTrace < rampDownStart;
    rampDownIdx = tTrace >= rampDownStart & tTrace < rampDownEnd;

    fTrace(rampUpIdx) = forceTarget * (tTrace(rampUpIdx) - rampUpStart) / tSlope;
    fTrace(plateauIdx) = forceTarget;
    fTrace(rampDownIdx) = forceTarget * (1 - (tTrace(rampDownIdx) - rampDownStart) / tSlope);
end

function [tTrace, fTrace] = force_trace_triang(fs_force)
    duration = 25;
    target = 30;
    tTrace = 0:1/fs_force:duration;
    fTrace = zeros(size(tTrace));

    quarter = duration / 4;
    idx1 = tTrace < quarter;
    idx2 = tTrace >= quarter & tTrace < 2 * quarter;
    idx3 = tTrace >= 2 * quarter & tTrace < 3 * quarter;
    idx4 = tTrace >= 3 * quarter;

    fTrace(idx1) = target * tTrace(idx1) / quarter;
    fTrace(idx2) = target * (1 - (tTrace(idx2) - quarter) / quarter);
    fTrace(idx3) = -target * (tTrace(idx3) - 2 * quarter) / quarter;
    fTrace(idx4) = -target * (1 - (tTrace(idx4) - 3 * quarter) / quarter);
end

function recordedForce = cropCircularForceData(forceData, recordStartForce, recordEndForce, maxForceSamples)
    if isempty(recordStartForce) || isempty(recordEndForce)
        recordedForce = [];
        return
    end

    recordStartForce = max(1, min(recordStartForce, maxForceSamples));
    recordEndForce = max(1, min(recordEndForce, maxForceSamples));

    if recordStartForce <= recordEndForce
        recordedForce = forceData(recordStartForce:recordEndForce, :);
    else
        recordedForce = [forceData(recordStartForce:end, :); forceData(1:recordEndForce, :)];
    end
end

function closeSerialObject(serialObj)
    if ~isempty(serialObj) && isvalid(serialObj)
        fclose(serialObj);
        delete(serialObj);
        clear serialObj
        disp('Arduino force stream closed.');
    end
end
