function StreamForceAndEmg(config)
% streamForceAndEmgV2 uses the config struct. with the user settings in
% config records force and Emg with low fs realtime feedback.
%% 1. Read and setup configuration

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

%% 2. choosing calibration file 
% Select a calibration file using uigetfile . Press Cancel to use the default values.
calibrationFile = config.forceCalibrationFile;
if isempty(calibrationFile) && config.promptForceCalibration
    ScriptDir = fileparts(mfilename('fullpath'));
    [calibrationFileName, path] = uigetfile(fullfile(fileparts(ScriptDir), '*.mat'),'Select calibration file, or press Cancel to use defaults');
    if ~isequal(calibrationFileName, 0)
        calibrationFile = fullfile(path, calibrationFileName);
    end
end


%% 3. load calibration values
if ~isempty(calibrationFile)
    calibrationData = load(calibrationFile, 'calibrationFactors', 'zeroValues', 'reverseStates');

    calibrationFactors = calibrationData.calibrationFactors;
    zeroValues = calibrationData.zeroValues;
    reverseStates = calibrationData.reverseStates;

    disp(['Loaded calibration data from : ', calibrationFile]);
else
    calibrationFactors = defaultCalibrationFactors;
    zeroValues = defaultZeroValues;
    reverseStates = defaultReverseStates;
    disp('No calibration file selected. Using default calibration values.');
end
% Save the source filename, rather than duplicating calibration arrays.
% An empty name means default calibration values were used.
calibrationFileName = '';
if ~isempty(calibrationFile)
    [~, calibrationBaseName, calibrationExtension] = fileparts(calibrationFile);
    calibrationFileName = [calibrationBaseName calibrationExtension];
end

%% 4. Initialize figure and axes
[fig, ax_f, ax_emg, btnClose, btnZero, btnRecord, btnRecordTracking, ...
    forceChanDropdown, traceTypeDropdown, tWaitBox, tSlopeBox, tPlateauBox, ...
    forceTargetBox, forceSignLabel, forceSignCheckbox, participantIDBox, ...
    trialBox, sessionBox] = setupRecordingFigure(EmgToggle, numel(emgPreviewRows));

%% 5. Setup Force streaming from Arduino
serialObj = initializeArduinoForceStream(ard_port); % MATLAB’s communication link to the Arduino
serialCleanup = onCleanup(@() closeSerialObject(serialObj)); 

%% 6. Setup EMG streaming and plotting when enabled
if EmgToggle
    emgCfg = makeNovecentoConfig(emgBlockDurationSec,emgActiveInputs,emgChannels);
    novecentoDev = novecento_connect(emgCfg);
    emgCleanup = onCleanup(@() closeEMGStream(novecentoDev, true)); % clean up TCP

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

%% 7. Initialize variables
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

forceLines = initializeStreamForcePlot(ax_f, numForceChan);

%% 8. Main loop to stream force data at 50 Hz for plotting
forceStreamTime = tic;

while ishandle(fig) % continue until main fig is on
    loopStartTime = tic;
    try
        %% ----------- Force data streaming -----------
        while serialObj.NumBytesAvailable > 0
            % Expected Arduino line format:timestamp,force1,force2,force3
            serialLine = readline(serialObj);
            fSample = sscanf(char(serialLine), '%f,%f,%f,%f');

            if numel(fSample) >= 4 % The sample is processed if it contains at least four numbers:
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
                    updateStreamForcePlot(ax_f, forceLines, forceData, fs_force, numForceChan, ...
                        displayTime, bufferTime, forceTarget, forceMin, currentForceIndex);
                end
                forceTimes(currentForceIndex) = toc(forceStreamTime);
            end
        end

        %% ----------- EMG data streaming and plotting -----------
        if EmgToggle
            rawEMG = novecento_read_emg_block(novecentoDev,emgCfg.activeInputs, emgSamplesPerBlock); % one EMG block
            emgSample = double(rawEMG(emgCfg.emgChannels, :)); % 64 out of 70 from novecento

            nEMGSamples = size(emgSample, 2);
            nextEMGIndex = currentEMGIndex + nEMGSamples;

            if nextEMGIndex <= maxEMGSamples
                emgData(:, currentEMGIndex + 1:nextEMGIndex) = emgSample;
                currentEMGIndex = nextEMGIndex;
            else
                % Start a fresh EMG buffer after the configured minutes.
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
                            muEditGridName, muEditMuscle, fs_force);
                        signal.calibrationFileName = calibrationFileName;
                        % EMG/force recordings and EMG rate are already in signal.
                        save(filename, 'signal', '-v7.3');
                    else
                        save(filename, 'recordedForce', ...
                            'fs_force', ...
                            'calibrationFileName');
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
                        muEditGridName, muEditMuscle, fs_force);
                    signal.calibrationFileName = calibrationFileName;
                    % EMG/force recordings and EMG rate are already in signal.
                    save(filename, 'signal', '-v7.3');
                else
                    save(filename, 'recordedForce', ...
                        'fs_force', ...
                        'calibrationFileName');
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
%% helper 1
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

%% helper 2
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


%% helper 3
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


%% helper 4
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

%% clean serial port
function closeSerialObject(serialObj)
    if ~isempty(serialObj) && isvalid(serialObj)
        delete(serialObj);
        disp('Arduino force stream closed.');
    end
end

%% clean TCP
function closeEMGStream(novecentoDev, EmgToggle)
    if ~EmgToggle || isempty(novecentoDev)
        return;
    end

    try
        novecento_disconnect(novecentoDev);
    catch
    end
end
