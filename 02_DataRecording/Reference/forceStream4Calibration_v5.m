clc;
close all;
clear all;

%% Parameters

% IMPORTANT: FILL SUBJECT ID AT THE BEGINNING
participantID = "rm"; % used to load existing calibration file

ard_port = 'COM4'; % Modify depending on the PC or laptop used
fs_force = 50;  % Force sampling frequency
fs_emg = 2000;  % EMG sampling frequency
numForceChan = 3;  % Set to 1, 2, or 3 based on the number of force channels
displayTime = 10;  % Display 10 seconds of data with extra 5 seconds of empty space
calibrationTime = 15;  % Time for calibration recording in seconds
zeroTime = 3;  % Time for zero value calculation in seconds
toggleEMG = false; % When true, stream EMG
maxDuration = 10 * 60; % Maximum recording time (10 minutes in seconds)

% Preallocate size for 10 minutes worth of data
maxForceSamples = fs_force * maxDuration;
maxEMGSamples = fs_emg * maxDuration;

% Initialize data storage
forceData = zeros(maxForceSamples, numForceChan);
if toggleEMG
    emgData = zeros(128, maxEMGSamples);
end

currentForceIndex = 0;
currentEMGIndex = 0;

% Initialize figure and axes
[fig, ax_f, btnClose, btnCalibrate1, btnCalibrate2, btnCalibrate3, txtCalibrate1, txtCalibrate2, txtCalibrate3, ...
    btnSaveZero, txtStatus, btnReverse1, btnReverse2, btnReverse3, btnSaveCalib, participantIDBox] = setupFigureForCalibration(numForceChan);

% Setup Force and EMG streaming
serialObj = initializeArduinoStream(ard_port);

if toggleEMG
    [tcpSocket, NumEMGChanSessn, TCPPort, OffsetEMG, PlotTime, DeviceEN, EMG, NumChan, Mode, SyncStatChan, ...
        TotNumChan, TotNumByte, ConfString, blockData] = setupSyncstationWithSessantaquattro();
end

% Initialize variables for storing data
forceData = [];
rawForce = [];
if toggleEMG
    emgData = [];
end

calibrationInProgress = [false, false, false];
calibrationStartTime = uint64([0, 0, 0]);

% Structure to store calibration data for each channel
channelCalibData = struct();
for i = 1:numForceChan
    channelCalibData(i).forceData = [];
    if toggleEMG
        channelCalibData(i).emgData = [];
    end
    channelCalibData(i).forceIndexes = struct('start', [], 'end', []);
    if toggleEMG
        channelCalibData(i).emgIndexes = struct('start', [], 'end', []);
    end
end

% Smoothing parameters
windowSize = 0.25;  % Moving average window size in seconds (250 ms)
fs_window = round(windowSize * fs_force);
alpha = 0.3; % Exponential moving average parameter
spikeThreshold = 50; % Threshold for spike detection

% Initialize animatedline objects for force plotting
forceLines = initializeForcePlot(ax_f, numForceChan);

% Load calibration file if it exists
calibrationFile = strcat("S",participantID,"_calibrationData.mat");
if isfile(calibrationFile)
    load(calibrationFile, 'calibrationFactors', 'zeroValues', 'reverseStates');
else
    calibrationFactors = [1e6, 0.8e6, 0.8e6];
    zeroValues = [-400, 150, 750];
    reverseStates = [false, true, false];
end

% Temporary variables for calibration during execution (won't affect real calibration yet)
tempCalibrationFactors = calibrationFactors;
tempZeroValues = zeroValues;

%% Main loop to stream data
while ishandle(fig)
    try
        % Force data streaming and processing
        if serialObj.BytesAvailable > 0
            % Read force data
            fSample = fscanf(serialObj, '%f,%f,%f,%f');
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
            rawForce(currentForceIndex, :) = forceSample; % Store raw force data

            if currentForceIndex > maxForceSamples
                currentForceIndex = 1; % Wrap around if exceeding preallocated size
            end  
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
            alpha = 0.3;
            if currentForceIndex > 1
                filteredForce = alpha * filteredForce + (1 - alpha) * forceData(currentForceIndex - 1, :);
            end

            % Store filtered data
            forceData(currentForceIndex, :) = filteredForce;

            % EMG data streaming if enabled
            if toggleEMG
                emgSample = streamEMGData(tcpSocket, NumEMGChanSessn, blockData, TotNumByte, PlotTime, DeviceEN, EMG, NumChan, fs_emg);
                currentEMGIndex = currentEMGIndex + size(emgSample, 2);
                if currentEMGIndex > maxEMGSamples
                    currentEMGIndex = 1;
                end
                emgData(:, currentEMGIndex-size(emgSample,2)+1:currentEMGIndex) = emgSample;
            end

            % Check calibration buttons and handle calibration
            for i = 1:numForceChan
                if eval(['btnCalibrate', num2str(i), '.Value']) && ~calibrationInProgress(i)
                    calibrationInProgress(i) = true;
                    calibrationStartTime(i) = tic;
                    channelCalibData(i).forceIndexes.start = currentForceIndex;
                    if toggleEMG
                        channelCalibData(i).emgIndexes.start = currentEMGIndex;
                    end
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
                        if toggleEMG
                            channelCalibData(i).emgIndexes.end = currentEMGIndex;
                        end
                        
                        % Store calibration data
                        calibForceData = rawForce(channelCalibData(i).forceIndexes.start:channelCalibData(i).forceIndexes.end, i);
                        channelCalibData(i).forceData = calibForceData;
                        if toggleEMG
                            calibEMGData = emgData(:, channelCalibData(i).emgIndexes.start:channelCalibData(i).emgIndexes.end);
                            channelCalibData(i).emgData = calibEMGData;
                        end
                        
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
                zeroData = rawForce(end-zeroTime*fs_force:end, :);
                tempZeroValues = mean(zeroData);  % Store in temporary variable
                btnSaveZero.Value = false;
                txtStatus.String = 'Zeroing complete!';
            end

            % Update Force Plot
            updateForcePlot_v5(ax_f, forceLines, forceData, fs_force, numForceChan, displayTime, 5);

            % Check reverse buttons
            for i = 1:numForceChan
                reverseStates(i) = eval(['btnReverse', num2str(i), '.Value']);
            end

            % Save calibration data (only apply the temp values now)
            if btnSaveCalib.Value
                participantID = participantIDBox.String;
                if isempty(participantID)
                    txtStatus.String = 'Error: Please enter Participant ID';
                else
                    calibrationFile = sprintf('S%s_calibrationData.mat', participantID);
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
            if ~isempty(serialObj) && isvalid(serialObj)
                fclose(serialObj);
                delete(serialObj);
                clear serialObj
            end
        
            % Close the TCP socket (if EMG is enabled)
            if toggleEMG 
                if ~isempty(tcpSocket)
                    fclose(tcpSocket);
                    delete(tcpSocket);
                    clear tcpSocket
                end
            end
           break;
       end

    catch ME
        disp(['Error occurred: ', ME.message]);
        txtStatus.String = 'Error occurred!';
    end

    drawnow;
end


%% Helper Functions

function [fig, ax_f, btnClose, btnCalibrate1, btnCalibrate2, btnCalibrate3, txtCalibrate1, txtCalibrate2, txtCalibrate3, ...
    btnSaveZero, txtStatus, btnReverse1, btnReverse2, btnReverse3, btnSaveCalib, participantIDBox] = setupFigureForCalibration(numForceChan)
    % Create figure
    fig = figure('Name', 'Force Calibration', 'NumberTitle', 'off', 'Position', [400, 400, 1600, 600]);
    
    % Create force plot axes
    ax_f = subplot(1, 1, 1);
    set(ax_f, 'Position', [0.05, 0.1, 0.75, 0.8]);

    title(ax_f, 'Force Data');
    xlabel(ax_f, 'Time (s)');
    ylabel(ax_f, 'Force (N)');
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

function [forceLines] = initializeForcePlot(ax, numForceChannels)
    colors = ['r', 'b', 'g'];
    forceLines = gobjects(1, numForceChannels);
    
    for i = 1:numForceChannels
        forceLines(i) = animatedline(ax, 'Color', colors(i), 'LineWidth', 1.5);
    end
end