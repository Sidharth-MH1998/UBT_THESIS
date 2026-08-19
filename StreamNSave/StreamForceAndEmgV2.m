function StreamForceAndEmgV2(config)
%STREAMFORCEANDEMGV2 Stream, display, and record force and EMG signals.
% During recording, all force and EMG samples are stored. The EMG preview
% displays only selected channels to keep the live plot responsive.
%
% When EMG streaming is enabled, the saved MAT file includes:
%   recordedForce - Recorded force samples x 3 force channels.
%   recordedEMG   - 128 EMG channels x recorded EMG samples.
%   emgData       - Complete EMG circular buffer.
%   fs_force      - Force sampling frequency.
%   fs_emg        - EMG sampling frequency.

%% Read configuration
requiredFields = {'arduinoPort','forceFs','maxDurationSec','emgEnabled', ...
    'emgActiveInputs','emgChannels','emgPreviewRows', ...
    'emgBlockDurationSec','muEditGridName','muEditMuscle', ...
    'emgPlotUpdateRate','emgDisplayDecimation','displayTimeSec', ...
    'bufferTimeSec','forcePlotUpdateRate','forceCalibrationFile', ...
    'promptForceCalibration','defaultCalibrationFactors', ...
    'defaultZeroValues','defaultReverseStates'};
for fieldIdx = 1:numel(requiredFields)
    if ~isfield(config, requiredFields{fieldIdx})
        error('Missing configuration field: config.%s', requiredFields{fieldIdx});
    end
end

ard_port = config.arduinoPort;
fs_force = config.forceFs;
maxDuration = config.maxDurationSec;
EmgToggle = config.emgEnabled;
emgActiveInputs = config.emgActiveInputs;
emgChannels = config.emgChannels;
emgPreviewRows = config.emgPreviewRows;
emgBlockDurationSec = config.emgBlockDurationSec;
muEditGridName = config.muEditGridName;
muEditMuscle = config.muEditMuscle;
emgPlotUpdateRate = config.emgPlotUpdateRate;
emgDisplayDecimation = config.emgDisplayDecimation;

numForceChan = 3;
displayTime = config.displayTimeSec;
bufferTime = config.bufferTimeSec;
plotUpdateRate = config.forcePlotUpdateRate;
% With 50-Hz force and a 10-Hz plot, redraw after every five new samples.
plotUpdateInterval = round(fs_force / plotUpdateRate);

% Preallocate size for 10 minutes worth of data
maxForceSamples = fs_force * maxDuration;
forceData = zeros(maxForceSamples, numForceChan);
currentForceIndex = 0;

% Initialize default calibration values
defaultCalibrationFactors = config.defaultCalibrationFactors;
defaultZeroValues = config.defaultZeroValues;
defaultReverseStates = config.defaultReverseStates;

%% choosing calibration file 
% Select a calibration file using uigetfile . Press Cancel to use the default values.
calibrationFile = config.forceCalibrationFile;
if isempty(calibrationFile) && config.promptForceCalibration
    forceScriptDir = fileparts(mfilename('fullpath'));
    [calibrationFileName, calibrationFolder] = uigetfile( ...
        fullfile(forceScriptDir, '*.mat'), ...
        'Select calibration file, or press Cancel to use defaults');
    if ~isequal(calibrationFileName, 0)
        calibrationFile = fullfile(calibrationFolder, calibrationFileName);
    end
end

if ~isempty(calibrationFile)
    calibrationData = load(calibrationFile, 'calibrationFactors', 'zeroValues', 'reverseStates');

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

%% Initialize figure and axes
[fig, ax_f, ax_emg, btnClose, btnZero, btnRecord, btnRecordTracking, ...
    forceChanDropdown, traceTypeDropdown, tWaitBox, tSlopeBox, tPlateauBox, ...
    forceTargetBox, forceSignLabel, forceSignCheckbox, participantIDBox, ...
    trialBox, sessionBox] = setupRecordingFigure( ...
    EmgToggle, numel(emgPreviewRows));

%% Setup Force streaming from Arduino
serialObj = initializeArduinoStream(ard_port); % MATLAB’s communication link to the Arduino
serialCleanup = onCleanup(@() closeSerialObject(serialObj));

%% Setup EMG streaming and plotting when enabled
if EmgToggle
    emgCfg = makeNovecentoConfig( ...
        emgBlockDurationSec,emgActiveInputs,emgChannels);
    novecentoDev = novecento_connect(emgCfg);
    emgCleanup = onCleanup(@() closeEMGStream(novecentoDev, true));
    %sanity check
    activeFs = novecentoDev.fsInput(emgCfg.activeInputs);
    if any(activeFs <= 0) || numel(unique(activeFs)) ~= 1
        error(['Invalid Novecento input configuration. Active inputs: %s; ' ...
            'detected channel counts: %s; sampling rates: %s; ' ...
            'probe type codes: %s.'], ...
            mat2str(emgCfg.activeInputs), ...
            mat2str(novecentoDev.NumChan(emgCfg.activeInputs).'), ...
            mat2str(activeFs.'), ...
            mat2str(novecentoDev.Settings(emgCfg.activeInputs + 1)));
    end
    fs_emg = activeFs(1);
    emgSamplesPerBlock = round(fs_emg * emgCfg.blockDurationSec);
    maxEMGSamples = fs_emg * maxDuration;
    emgData = zeros(numel(emgCfg.emgChannels), maxEMGSamples);
    currentEMGIndex = 0;
    emgPlotCounter = 0;
    emgPlotInterval = max(1, round(1 /(emgCfg.blockDurationSec * emgPlotUpdateRate)));

    emgFig = fig; % Force and EMG now share the same window.
else
    novecentoDev = [];
    emgCleanup = [];
    emgData = [];
    currentEMGIndex = 0;
    emgFig = [];
end

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
recordStartEMG = [];
recordEndEMG = [];
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
        while serialObj.NumBytesAvailable > 0
            % Expected Arduino line format:timestamp,force1,force2,force3
            serialLine = readline(serialObj);
            fSample = sscanf(char(serialLine), '%f,%f,%f,%f');

            if numel(fSample) >= 4
                nextForceIndex = currentForceIndex + 1;
                if nextForceIndex > maxForceSamples
                    nextForceIndex = 1;
                end

                tStamps(nextForceIndex) = fSample(1); % sample number 
                forceSample = fSample(2:4); % three force channels

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
                calibratedForce = (forceSample(1:numForceChan)' - zeroValues(1:numForceChan))./ calibrationFactors(1:numForceChan) * 100;

                % Step 3: Store calibrated force data
                currentForceIndex = nextForceIndex;
                forceData(currentForceIndex, :) = calibratedForce;

                % Step 4: Apply exponential moving average filter  for smoothing
                filteredForce = calibratedForce;
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
        end

        % ----------- EMG data streaming and plotting -----------
        if EmgToggle
            rawEMG = novecento_read_emg_block(novecentoDev,emgCfg.activeInputs, emgSamplesPerBlock);
            emgSample = double(rawEMG(emgCfg.emgChannels, :));

            nEMGSamples = size(emgSample, 2);
            nextEMGIndex = currentEMGIndex + nEMGSamples;

            if nextEMGIndex <= maxEMGSamples
                emgData(:, currentEMGIndex + 1:nextEMGIndex) = emgSample;
                currentEMGIndex = nextEMGIndex;
            else
                % Start a fresh EMG buffer after the configured ten minutes.
                currentEMGIndex = nEMGSamples;
                emgData(:, 1:currentEMGIndex) = emgSample;
            end

            emgPlotCounter = emgPlotCounter + 1;
            if ishandle(emgFig) && mod(emgPlotCounter, emgPlotInterval) == 0
                updateLiveEMGPlot(ax_emg, emgData, currentEMGIndex,fs_emg, displayTime, emgPreviewRows, ...
                    emgCfg.emgChannels, emgDisplayDecimation);
            end
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
            if EmgToggle
                recordStartEMG = currentEMGIndex + 1;
            end

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

            forceTraceLine = animatedline(ax_f, 'Color', 'k', 'LineWidth', 1, 'LineStyle', '-');
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
                if EmgToggle
                    recordEndEMG = currentEMGIndex;
                end

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
                    if EmgToggle
                        recordedEMG = cropCircularEMGData(emgData, recordStartEMG, ...
                            recordEndEMG, maxEMGSamples);
                        emgChannels = emgCfg.emgChannels;
                        activeEMGInputs = emgCfg.activeInputs;
                        signal = buildMUeditSignal(recordedEMG, fs_emg, ...
                            recordedForce, digit, forceTarget, activeEMGInputs, ...
                            muEditGridName, muEditMuscle);
                        save(filename, 'forceData', 'recordedForce', ...
                            'recordStartForce', 'recordEndForce', 'fs_force', ...
                            'calibrationFactors', 'zeroValues', 'reverseStates', ...
                            'tStamps', 'recordedEMG', 'recordStartEMG', ...
                            'recordEndEMG', 'fs_emg', 'emgChannels', ...
                            'activeEMGInputs', 'signal', '-v7.3');
                    else
                        save(filename, 'forceData', 'recordedForce', ...
                            'recordStartForce', 'recordEndForce', 'fs_force', ...
                            'calibrationFactors', 'zeroValues', 'reverseStates', ...
                            'tStamps');
                    end

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
            if EmgToggle
                recordStartEMG = currentEMGIndex + 1;
            end
            ax_f.Color = [1, 0.95, 0.9];
            disp('Manual recording started.');
        elseif ~btnRecord.Value && recording
            recording = false;
            recordEndForce = currentForceIndex;
            if EmgToggle
                recordEndEMG = currentEMGIndex;
            end
            ax_f.Color = [1, 1, 1];

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
                filename = sprintf('S%s_ss%d_f%d_t%d.mat', participantID, session, forceTarget, trial);

                recordedForce = cropCircularForceData(forceData, recordStartForce, recordEndForce, maxForceSamples);
                if EmgToggle
                    recordedEMG = cropCircularEMGData(emgData, recordStartEMG, ...
                        recordEndEMG, maxEMGSamples);
                    emgChannels = emgCfg.emgChannels;
                    activeEMGInputs = emgCfg.activeInputs;
                    signal = buildMUeditSignal(recordedEMG, fs_emg, ...
                        recordedForce, digit, forceTarget, activeEMGInputs, ...
                        muEditGridName, muEditMuscle);
                    save(filename, 'forceData', 'recordedForce', ...
                        'recordStartForce', 'recordEndForce', 'fs_force', ...
                        'calibrationFactors', 'zeroValues', 'reverseStates', ...
                        'tStamps', 'recordedEMG', 'recordStartEMG', ...
                        'recordEndEMG', 'fs_emg', 'emgChannels', ...
                        'activeEMGInputs', 'signal', '-v7.3');
                else
                    save(filename, 'forceData', 'recordedForce', ...
                        'recordStartForce', 'recordEndForce', 'fs_force', ...
                        'calibrationFactors', 'zeroValues', 'reverseStates', ...
                        'tStamps');
                end

                disp(['Recording saved as: ', filename]);
            end
        end

        % Check if the close button is pressed
        if btnClose.Value
            closeSerialObject(serialObj);
            closeEMGStream(novecentoDev, EmgToggle);
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
    closeEMGStream(novecentoDev, EmgToggle);
end

clear emgCleanup serialCleanup;

end

%% Local functions

function [fig, ax_f, ax_emg, btnClose, btnZero, btnRecord, btnRecordTracking, ...
    forceChanDropdown, traceTypeDropdown, tWaitBox, tSlopeBox, tPlateauBox, ...
    forceTargetBox, forceSignLabel, forceSignCheckbox, participantIDBox, ...
    trialBox, sessionBox] = setupRecordingFigure(emgEnabled, numPreviewChannels)

    fig = figure('Name', 'Force and EMG Recording', ...
        'NumberTitle', 'off', ...
        'Color', [0.94, 0.94, 0.94], ...
        'Position', [60, 50, 1450, 850]);

    ax_f = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.055, 0.56, 0.70, 0.39]);
    hold(ax_f, 'on');
    grid(ax_f, 'on');
    xlabel(ax_f, 'Time (s)');
    ylabel(ax_f, 'Force (% calibrated)');
    title(ax_f, 'Live Force Data');
    ylim(ax_f, [-10 110]);

    ax_emg = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.055, 0.08, 0.70, 0.37]);
    hold(ax_emg, 'on');
    grid(ax_emg, 'on');
    title(ax_emg, sprintf('Live Novecento EMG - %d preview channels', ...
        numPreviewChannels));
    xlabel(ax_emg, 'Time (s)');
    ylabel(ax_emg, 'Novecento channel');
    if ~emgEnabled
        title(ax_emg, 'EMG disabled');
        set(ax_emg, 'Visible', 'off');
    end

    controls = uipanel('Parent', fig, 'Title', 'Recording Controls', ...
        'Units', 'normalized', 'Position', [0.78, 0.05, 0.20, 0.90], ...
        'BackgroundColor', fig.Color);
    labelX = 0.08; fieldX = 0.53; labelW = 0.42; fieldW = 0.39;
    rowY = [0.91 0.83 0.75 0.67 0.59 0.51 0.43 0.35 0.27];
    labels = {'Participant','Session','Trial','Digit/Channel','Trace', ...
        'Wait (s)','Slope (s)','Plateau (s)','Target (%)'};
    for k = 1:numel(labels)
        uicontrol(controls, 'Style', 'text', 'String', labels{k}, ...
            'Units', 'normalized', 'Position', [labelX rowY(k) labelW 0.045], ...
            'HorizontalAlignment', 'left', 'BackgroundColor', controls.BackgroundColor);
    end
    participantIDBox = uicontrol(controls, 'Style', 'edit', 'String', '', ...
        'Units', 'normalized', 'Position', [fieldX rowY(1) fieldW 0.05]);
    sessionBox = uicontrol(controls, 'Style', 'edit', 'String', '1', ...
        'Units', 'normalized', 'Position', [fieldX rowY(2) fieldW 0.05]);
    trialBox = uicontrol(controls, 'Style', 'edit', 'String', '1', ...
        'Units', 'normalized', 'Position', [fieldX rowY(3) fieldW 0.05]);
    forceChanDropdown = uicontrol(controls, 'Style', 'popupmenu', ...
        'String', {'1', '2', '3'}, 'Value', 2, 'Units', 'normalized', ...
        'Position', [fieldX rowY(4) fieldW 0.05]);
    traceTypeDropdown = uicontrol(controls, 'Style', 'popupmenu', ...
        'String', {'Trapezium', 'Triangular'}, 'Units', 'normalized', ...
        'Position', [fieldX rowY(5) fieldW 0.05]);
    tWaitBox = uicontrol(controls, 'Style', 'edit', 'String', '5', ...
        'Units', 'normalized', 'Position', [fieldX rowY(6) fieldW 0.05]);
    tSlopeBox = uicontrol(controls, 'Style', 'edit', 'String', '3', ...
        'Units', 'normalized', 'Position', [fieldX rowY(7) fieldW 0.05]);
    tPlateauBox = uicontrol(controls, 'Style', 'edit', 'String', '5', ...
        'Units', 'normalized', 'Position', [fieldX rowY(8) fieldW 0.05]);
    forceTargetBox = uicontrol(controls, 'Style', 'edit', 'String', '30', ...
        'Units', 'normalized', 'Position', [fieldX rowY(9) fieldW 0.05]);

    forceSignCheckbox = uicontrol(controls, 'Style', 'checkbox', ...
        'String', 'Extension +', 'Value', 0, 'Units', 'normalized', ...
        'Position', [0.08, 0.19, 0.84, 0.05], ...
        'BackgroundColor', controls.BackgroundColor);
    forceSignLabel = uicontrol(controls, 'Style', 'text', ...
        'String', sprintf('%s\n%s', '(+): Flexion', '(-): Extension '), ...
        'Units', 'normalized', 'Position', [0.08, 0.125, 0.84, 0.06], ...
        'HorizontalAlignment', 'left', 'BackgroundColor', controls.BackgroundColor);

    btnRecordTracking = uicontrol(controls, 'Style', 'togglebutton', ...
        'String', 'Track Record', 'Units', 'normalized', ...
        'Position', [0.08, 0.065, 0.40, 0.05]);
    btnRecord = uicontrol(controls, 'Style', 'togglebutton', ...
        'String', 'Record', 'Units', 'normalized', ...
        'Position', [0.52, 0.065, 0.40, 0.05]);
    btnZero = uicontrol(controls, 'Style', 'togglebutton', ...
        'String', 'Zero', 'Units', 'normalized', ...
        'Position', [0.08, 0.005, 0.40, 0.05]);
    btnClose = uicontrol(controls, 'Style', 'togglebutton', ...
        'String', 'Close', 'BackgroundColor', [0.85 0.25 0.25], ...
        'Units', 'normalized', 'Position', [0.52, 0.005, 0.40, 0.05]);
end
% connect to arduino
function serialObj = initializeArduinoStream(ard_port)
    availablePorts = serialportlist("available");
    if ~any(strcmpi(availablePorts, ard_port))
        error('Arduino port %s is not available. Available ports: %s', ...
            ard_port, strjoin(cellstr(availablePorts), ', '));
    end

    serialObj = serialport(ard_port, 115200, 'Timeout', 2);
    configureTerminator(serialObj, "LF");
    pause(1);
    flush(serialObj, "input");
    disp(['Arduino force stream connected on ', ard_port]);
end
% initialize force plot
function forceLines = initializeForcePlot(ax_f, numForceChan)
    colors = lines(numForceChan);
    forceLines = gobjects(numForceChan, 1);

    for i = 1:numForceChan
        forceLines(i) = animatedline(ax_f, 'Color', colors(i, :), 'LineWidth', 1.5);
    end

    legend(ax_f, {'Load cell 1', 'Load cell 2', 'Load cell 3'}, 'Location', 'northwest');
end
% update the force plot
function updateForcePlot(ax_f, forceLines, forceData, fs_force, numForceChan, ...
    displayTime, bufferTime, ~, ~, currentForceIndex)

    if currentForceIndex < 1 % first sample
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
    ylim(ax_f, [-10 110]);
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

function recordedEMG = cropCircularEMGData(emgData, recordStartEMG, recordEndEMG, maxEMGSamples)
    if isempty(recordStartEMG) || isempty(recordEndEMG) || recordEndEMG < 1
        recordedEMG = [];
        return
    end

    recordStartEMG = max(1, min(recordStartEMG, maxEMGSamples));
    recordEndEMG = max(1, min(recordEndEMG, maxEMGSamples));

    if recordStartEMG <= recordEndEMG
        recordedEMG = emgData(:, recordStartEMG:recordEndEMG);
    else
        recordedEMG = [emgData(:, recordStartEMG:end), ...
            emgData(:, 1:recordEndEMG)];
    end
end

function closeSerialObject(serialObj)
    if ~isempty(serialObj) && isvalid(serialObj)
        delete(serialObj);
        disp('Arduino force stream closed.');
    end
end

function signal = buildMUeditSignal(recordedEMG, fsEMG, recordedForce, ...
    forceChannel, forceTarget, activeInputs, gridName, muscleName)
% Build the MAT-file structure expected by MUedit.
    nSamples = size(recordedEMG, 2);
    nGrids = numel(activeInputs);

    signal = struct();
    signal.data = recordedEMG;
    signal.fsamp = fsEMG;
    signal.nChan = size(recordedEMG, 1);
    signal.ngrid = nGrids;
    signal.gridname = repmat({gridName}, 1, nGrids);
    signal.muscle = repmat({muscleName}, 1, nGrids);
    signal.target = repmat(forceTarget, 1, nSamples);

    forceChannel = min(max(round(forceChannel), 1), size(recordedForce, 2));
    if isempty(recordedForce) || nSamples == 0
        signal.path = zeros(1, nSamples);
    elseif size(recordedForce, 1) == 1
        signal.path = repmat(recordedForce(1, forceChannel), 1, nSamples);
    else
        sourcePosition = linspace(0, 1, size(recordedForce, 1));
        emgPosition = linspace(0, 1, nSamples);
        signal.path = interp1(sourcePosition, ...
            recordedForce(:, forceChannel).', emgPosition, 'linear');
    end
end

function updateLiveEMGPlot(ax_emg, emgData, currentEMGIndex, ...
    fs_emg, displayTime, previewRows, emgChannelLabels, displayDecimation)

    if currentEMGIndex < 1
        return;
    end

    previewRows = previewRows(previewRows >= 1 & previewRows <= size(emgData, 1));
    if isempty(previewRows)
        return;
    end
    nVisible = min(currentEMGIndex, round(displayTime * fs_emg));
    firstSample = currentEMGIndex - nVisible + 1;
    displayIndices = firstSample:displayDecimation:currentEMGIndex;
    visibleEMG = emgData(previewRows, displayIndices);
    labels = emgChannelLabels(previewRows);
    displayFs = fs_emg / displayDecimation;
    firstDisplaySample = (displayIndices(1) - 1) / displayDecimation + 1;

    updateStackedEMGPreview(ax_emg, visibleEMG, labels, ...
        displayFs, firstDisplaySample, displayTime);
end

function updateStackedEMGPreview(ax, block, channelLabels, fs, ...
    firstSample, visibleWindowSec)
% Smooth local EMG preview used only by StreamForceAndEmgV2.
    plotBlock = double(block);
    nChannels = size(plotBlock, 1);
    offset = max(max(std(plotBlock, 0, 2) * 6), 1);
    xSec = ((firstSample - 1):(firstSample + size(plotBlock, 2) - 2)) / fs;

    plotState = getappdata(ax, 'StreamForceEMGPlotState');
    needsInitialization = isempty(plotState) || ...
        ~isfield(plotState, 'lines') || ...
        numel(plotState.lines) ~= nChannels || ...
        ~all(isgraphics(plotState.lines));

    if needsInitialization
        hold(ax, 'on');
        plotState.lines = gobjects(nChannels, 1);
        for ch = 1:nChannels
            plotState.lines(ch) = plot(ax, nan, nan, 'LineWidth', 0.8);
        end
        hold(ax, 'off');
        setappdata(ax, 'StreamForceEMGPlotState', plotState);
    end

    for ch = 1:nChannels
        set(plotState.lines(ch), 'XData', xSec, ...
            'YData', plotBlock(ch,:) + offset * (ch - 1));
    end

    xEnd = max(xSec(end), visibleWindowSec);
    xlim(ax, [xEnd - visibleWindowSec xEnd]);
    yticks(ax, offset * (0:(nChannels - 1)));
    yticklabels(ax, cellstr(num2str(channelLabels(:))));
    ylim(ax, [-offset offset * nChannels]);
end

function closeEMGStream(novecentoDev, EmgToggle)
    if ~EmgToggle || isempty(novecentoDev)
        return;
    end

    try
        novecento_disconnect(novecentoDev);
    catch
    end
end
%% Novecento configuration 
function cfg = makeNovecentoConfig(blockDurationSec,activeInputs,emgChannels)
    cfg = struct();
    cfg.socketTimeoutSec = 100;
    cfg.activeInputs = activeInputs;
    cfg.emgChannels = emgChannels;
    cfg.blockDurationSec = blockDurationSec;
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
    cfg.HRES(cfg.activeInputs) = 0;
    cfg.HPF(cfg.activeInputs) = 1;
    cfg.FsampCode(cfg.activeInputs) = 1;
end
