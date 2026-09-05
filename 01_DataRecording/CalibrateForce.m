clc;
close all;
clear;

%% User settings 
% IMPORTANT: FILL SUBJECT ID AT THE BEGINNING
% participantID = "SH"; % used to load existing calibration file

ard_port = 'COM4'; 
fs_force = 50;  % Force fs
numForceChan = 3;  % number of force channels
displayTime = 10;  % Display 10 seconds of data with extra 5 seconds of empty space
plotUpdateRate = 10; % Refresh plot at 10 Hz; data remains sampled/stored at 50 Hz
plotUpdateInterval = max(1, round(fs_force / plotUpdateRate)); % every 5th data plottted
calibrationTime = 15;  % Time for calibration recording in seconds
zeroTime = 3;  % Time for zero value calculation in seconds
maxDuration = 10 * 60; % Maximum recording time (10 minutes in seconds)

%% Load the data
% Select an existing calibration, or press Cancel to create a new one.
forceScriptDir = fileparts(mfilename('fullpath'));
[fileName, folderName] = uigetfile(fullfile(forceScriptDir, '*.mat'),'Select calibration file, or press Cancel for new calibration');

if isequal(fileName, 0)
    calibrationFile = '';
    calibrationFactors = [1e6, 0.8e6, 0.8e6];
    zeroValues = [-400, 150, 750];
    reverseStates = [false, true, false];
    disp('Starting a new calibration with default values.');
else
    calibrationFile = fullfile(folderName, fileName);
    calib = load(calibrationFile,'calibrationFactors','zeroValues','reverseStates');
    calibrationFactors = calib.calibrationFactors;
    zeroValues = calib.zeroValues;
    reverseStates = calib.reverseStates;
    disp(['Loaded calibration: ', calibrationFile]);
end

maxForceSamples = fs_force * maxDuration; % Preallocate size for 10 minutes worth of data
currentForceIndex = 0;

% Initialize figure and axes
[fig, ax_f, btnClose, btnCalibrate1, btnCalibrate2, btnCalibrate3, txtCalibrate1, txtCalibrate2, txtCalibrate3, ...
    btnSaveZero, txtStatus, btnReverse1, btnReverse2, btnReverse3, btnSaveCalib, participantIDBox] = setupFigureForCalibration(numForceChan);

% Keep the reverse controls consistent with the selected calibration file.
reverseButtons = [btnReverse1, btnReverse2, btnReverse3];
for i = 1:numForceChan
    reverseButtons(i).Value = reverseStates(i);
end

% Setup force streaming
serialObj = initializeArduinoStream(ard_port);
serialCleanup = onCleanup(@() closeSerialObject(serialObj));

% initiialise arrays to avoid resizing them during acquisition.
forceData = zeros(maxForceSamples, numForceChan); % Initialize data storage
rawForce = zeros(maxForceSamples, numForceChan);

calibrationInProgress = [false, false, false];
calibrationStartTime = uint64([0, 0, 0]);

% Structure to store calibration data for each channel
channelCalibData = struct();
for i = 1:numForceChan
    channelCalibData(i).forceData = [];
    channelCalibData(i).forceIndexes = struct('start', [], 'end', []);
end

% Smoothing parameters
windowSize = 0.25;  % Moving average window size in seconds (250 ms)
fs_window = round(windowSize * fs_force);
alpha = 0.6; % Faster exponential moving average response
spikeThreshold = 50; % Threshold for spike detection

% Initialize animatedline objects for force plotting
forceLines = initializeForcePlot(ax_f, numForceChan);

% Temporary variables for calibration during execution (won't affect real calibration yet)
tempCalibrationFactors = calibrationFactors;
tempZeroValues = zeroValues;

%% Main loop to stream data
while ishandle(fig)
    try
        % Force data streaming and processing
        if serialObj.NumBytesAvailable > 0
            % Read force data
            serialLine = char(readline(serialObj));
            fSample = sscanf(serialLine, '%f,%f,%f,%f');

            % Ignore startup messages, partial lines, or malformed packets.
            if numel(fSample) ~= 4
                fprintf('Ignored invalid Arduino line: %s\n', serialLine);
                continue;
            end

            forceSample = fSample(2:4);

            % Step 1: Apply reverse states if needed, and also check whether all channels should be reversed (for extension positive)
            for i = 1:numForceChan
                if reverseStates(i)
                    forceSample(i) = -forceSample(i);
                end
            end

            % Step 2: Apply zero values and calibration factors (calibrate the data using temp variables)
            calibratedForce = (forceSample(1:numForceChan)' - tempZeroValues(1:numForceChan)) ./ tempCalibrationFactors(1:numForceChan) * 100;
           
            % Step 3: Store the raw and calibrated force data in rawForce and forceData respectively
            currentForceIndex = currentForceIndex + 1;
            if currentForceIndex > maxForceSamples
                currentForceIndex = 1; % Wrap around if exceeding preallocated size
            end
            rawForce(currentForceIndex, :) = forceSample; % Store raw force data
            forceData(currentForceIndex, :) = calibratedForce; % Store calibrated data

            % Step 4a: Detect and replace spikes
            if currentForceIndex > 1
                deltaForce = abs(calibratedForce - forceData(currentForceIndex - 1, :));
                isSpike = deltaForce > spikeThreshold;
                filteredForce = calibratedForce;
                filteredForce(isSpike) = forceData(currentForceIndex - 1, isSpike); % Replace spikes
            else
                filteredForce = calibratedForce; % No previous data for first sample
            end

            % Step 4b: Apply exponential moving average for smoothing
            if currentForceIndex > 1
                filteredForce = alpha * filteredForce + (1 - alpha) * forceData(currentForceIndex - 1, :);
            end

            % Store filtered data
            forceData(currentForceIndex, :) = filteredForce;

            % Check calibration buttons and handle calibration
            for i = 1:numForceChan
                if eval(['btnCalibrate', num2str(i), '.Value']) && ~calibrationInProgress(i)
                    calibrationInProgress(i) = true;
                    calibrationStartTime(i) = tic;
                    channelCalibData(i).forceIndexes.start = currentForceIndex;
                    txtStatus.String = ['Calibrating Force Channel ', num2str(i)];
                end
            end

            % Process ongoing calibrations
            for i = 1:numForceChan
                if calibrationInProgress(i)
                    elapsedTime = toc(calibrationStartTime(i));
                    if elapsedTime <= calibrationTime
                        txtStatus.String = ['Calibrating Force Channel ', num2str(i), '... ', num2str(calibrationTime - round(elapsedTime)), 's remaining'];
                    else
                        % Finish calibration
                        calibrationInProgress(i) = false;
                        channelCalibData(i).forceIndexes.end = currentForceIndex;
                        
                        % Store calibration data
                        calibForceData = rawForce(channelCalibData(i).forceIndexes.start:channelCalibData(i).forceIndexes.end, i);
                        channelCalibData(i).forceData = calibForceData;
                        
                        % Calculate temporary calibration factor
                        movingAvg = movmean(calibForceData, fs_window);
                        tempCalibrationFactors(i) = max(movingAvg);  % Store in temporary variable
                        eval(['txtCalibrate', num2str(i), '.String = num2str(tempCalibrationFactors(i));']);
                        eval(['btnCalibrate', num2str(i), '.Value = false;']);
                        txtStatus.String = ['Calibration Complete for Force Channel ', num2str(i)];
                    end
                end
            end

            % Handle Save Zero button
            if btnSaveZero.Value
                txtStatus.String = 'Zeroing force values...';
                requiredZeroSamples = zeroTime * fs_force;

                if currentForceIndex >= requiredZeroSamples
                    zeroStart = currentForceIndex - requiredZeroSamples + 1;
                    zeroData = rawForce(zeroStart:currentForceIndex, :);
                    tempZeroValues = mean(zeroData, 1);
                    txtStatus.String = 'Zeroing complete!';
                else
                    txtStatus.String = sprintf( ...
                        'Not enough data for zeroing. Wait %.1f more seconds.', ...
                        (requiredZeroSamples - currentForceIndex) / fs_force);
                end

                btnSaveZero.Value = false;
            end

            % Update the display at 10 Hz. Acquisition, filtering, and data
            % storage above still execute for every valid 50 Hz sample.
            if mod(currentForceIndex, plotUpdateInterval) == 0
                validForceData = forceData(1:currentForceIndex, :);
                updateForcePlot_v5(ax_f, forceLines, validForceData,fs_force, numForceChan, displayTime, 5);
            end

            % Check reverse buttons
            for i = 1:numForceChan
                reverseStates(i) = reverseButtons(i).Value;
            end

            % Save calibration data (only apply the temp values now)
            if btnSaveCalib.Value
                participantID = participantIDBox.String;
                if isempty(participantID)
                    txtStatus.String = 'Error: Please enter Participant ID';
                else
                    calibrationFile = fullfile(forceScriptDir, ...
                        sprintf('S%s_calibrationData.mat', participantID));
                    % Apply the temporary calibration and zero values
                    calibrationFactors = tempCalibrationFactors;
                    zeroValues = tempZeroValues;
                    save(calibrationFile, 'calibrationFactors', 'zeroValues', 'reverseStates', 'channelCalibData');
                    btnSaveCalib.Value = false;
                    txtStatus.String = 'Calibration data saved.';
                end
            end
        end

        % Check close button
        if btnClose.Value
            % Close the serial object
            closeSerialObject(serialObj);
            break;
        end

    catch ME
        disp(['Error occurred: ', ME.message]);
        txtStatus.String = 'Error occurred!';
    end

    drawnow limitrate;
end

% Also close the serial port if the figure itself was closed.
closeSerialObject(serialObj);
clear serialCleanup;


%% Helper 1

function [fig, ax_f, btnClose, btnCalibrate1, btnCalibrate2, btnCalibrate3, txtCalibrate1, txtCalibrate2, txtCalibrate3, ...
    btnSaveZero, txtStatus, btnReverse1, btnReverse2, btnReverse3, btnSaveCalib, participantIDBox] = setupFigureForCalibration(numForceChan)
    % Create figure
    fig = figure('Name', 'Force Calibration', 'NumberTitle', 'off', 'Position', [400, 400, 1600, 600]);
    
    % Create force plot axes
    ax_f = subplot(1, 1, 1);
    set(ax_f, 'Position', [0.05, 0.1, 0.75, 0.8]);

    title(ax_f, 'Force data for calibration');
    xlabel(ax_f, 'Time (s)');
    ylabel(ax_f, 'Force (% MVC)');
    grid(ax_f, 'on');
    
    % Create control panel
    controlPanel = uipanel('Title', 'Controls', 'Position', [0.8, 0.1, 0.18, 0.8]);
    
    % Add Participant ID input
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Participant ID:', 'Position', [10, 460, 100, 20]);
    participantIDBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '', 'Position', [120, 460, 100, 25]);
 
    % Status text
    txtStatus = uicontrol(controlPanel, 'Style', 'text', 'String', 'Status: Ready', 'Position', [10, 430, 250, 30], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');
    
    % Calibrate Force Channels buttons
    for i = 1:numForceChan
        uicontrol(controlPanel, 'Style', 'text', 'String', ['Calibrate Force ', num2str(i)], ...
            'Position', [10, 400-40*(i-1), 100, 20]);
        eval(['txtCalibrate', num2str(i), ' = uicontrol(controlPanel, ''Style'', ''text'', ''String'', '''', ', ...
            '''Position'', [120, 400-40*(i-1), 60, 30]);']);
        eval(['btnCalibrate', num2str(i), ' = uicontrol(controlPanel, ''Style'', ''togglebutton'', ', ...
            '''String'', ''Calibrate'', ''Position'', [190, 400-40*(i-1), 60, 30]);']);
    end
    
    % Save Zero Button
    btnSaveZero = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Save Zero', 'Position', [10, 260, 100, 30]);

    % Reverse Force Buttons
    for i = 1:numForceChan
        uicontrol(controlPanel, 'Style', 'text', 'String', ['Reverse Force ', num2str(i)], ...
            'Position', [10, 200-40*(i-1), 100, 20]);
        eval(['btnReverse', num2str(i), ' = uicontrol(controlPanel, ''Style'', ''togglebutton'', ', ...
            '''String'', ''Reverse'', ''Position'', [120, 200-40*(i-1), 60, 30], ''BackgroundColor'', ''yellow'');']);
    end
    
    % Save Calibration Button
    btnSaveCalib = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Save Calibration', ...
        'Position', [100, 60, 100, 30], 'BackgroundColor', 'green');

    % Close button
    btnClose = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Close', ...
        'Position', [100, 20, 100, 30], 'BackgroundColor', 'red');
end

%% Helper 2
function [forceLines] = initializeForcePlot(ax, numForceChannels)
    colors = ['r', 'b', 'g'];
    forceLines = gobjects(1, numForceChannels);
    
    for i = 1:numForceChannels
        forceLines(i) = animatedline(ax, 'Color', colors(i), 'LineWidth', 1.5);
    end

    legendLabels = {'Thumb', 'Index finger', 'Middle finger'};
    legendLabels = legendLabels(1:numForceChannels);
    legend(ax, forceLines, legendLabels, 'Location', 'northwest');
end

function closeSerialObject(serialObj)
    if ~isempty(serialObj) && isvalid(serialObj)
        try
            flush(serialObj);
        catch
        end
        delete(serialObj);
    end
end
