clc
close all
clear all

% Parameters
ard_port = 'COM4'; % Modify based on the system: '/dev/cu.usbmodem1301' or 'COM3'
fs_force = 50;                     % Force sampling frequency (50 Hz)
fs_emg = 2000;                     % EMG sampling frequency (2000 Hz)
maxDuration = 10 * 60;             % Maximum recording time (10 minutes in seconds)

numForceChan = 3;                  % Number of force channels
numEMGChanToPlot = 4;              % Number of EMG channels to plot
displayTime = 15;                  % 10 seconds of data with 5 seconds extra space
bufferTime = 5;                    % Extra buffer time for plotting (5 seconds)
toggleEMG = false;                 % When true, stream EMG

% Median filter parameters
medianFilterLength = 10;            % Length of median filter (default 5 samples)

% Preallocate size for 10 minutes worth of data
maxForceSamples = fs_force * maxDuration; % 10 minutes of force data at 80 Hz
maxEMGSamples = fs_emg * maxDuration;     % 10 minutes of EMG data at 2000 Hz

forceData = zeros(maxForceSamples, numForceChan); % Preallocate force data
emgData = zeros(128, maxEMGSamples);              % Preallocate EMG data

currentForceIndex = 0; % Initialize index for force data
currentEMGIndex = 0;   % Initialize index for EMG data

% Initialize default calibration values
defaultCalibrationFactors = [10, 10, 10]; % Default 100% calibration values
defaultZeroValues = [0, 0, 0];            % Default zero values
defaultReverseStates = [false, false, false]; % No reverse by default

% Load calibration data if it exists, otherwise use default values
if exist('calibrationData.mat', 'file')
   calibrationData = load('calibrationData.mat');
   calibrationFactors = calibrationData.calibrationFactors;
   zeroValues = calibrationData.zeroValues;
   reverseStates = calibrationData.reverseStates;
else
   calibrationFactors = defaultCalibrationFactors;
   zeroValues = defaultZeroValues;
   reverseStates = defaultReverseStates;
end

% Initialize figure and axes with new participant ID, trial, and session inputs
[fig, ax_f, ax_emg, btnClose, btnZero, btnRecord, btnRecordTracking, forceChanDropdown, traceTypeDropdown, tWaitBox, tSlopeBox, tPlateauBox, forceTargetBox, forceSignLabel, forceSignCheckbox, participantIDBox, trialBox, sessionBox]...
    = setupFigure_v7(toggleEMG);

%%
% Setup Force streaming from Arduino
serialObj = initializeArduinoStream(ard_port);

% Initialize EMG streaming with Syncstation (if enabled)
if toggleEMG
   [tcpSocket, NumEMGChanSessn, TCPPort, OffsetEMG, PlotTime, DeviceEN, EMG, NumChan, Mode, SyncStatChan, TotNumChan, TotNumByte, ConfString, blockData] = setupSyncstationWithSessantaquattro();
end

% Initialize variables
forceTarget = 100;
forceMin = 0;
forceSample = [0;0;0];
tStamps = []; % timestamps coming from Arduino
lastForceIndex = 1;
lastEMGIndex = 1;
recording = false;
recordingTracking = false;
recordStartForce = [];
recordEndForce = [];
recordStartEMG = [];
recordEndEMG = [];
zeroed = false;

% Initialize arrays to store execution times
elapsedExecTimes = [];
forceTimes = [];
plotTimes = [];
emgTimes = [];

% Initialize animatedline objects for force and EMG plotting
forceLines = initializeForcePlot(ax_f, numForceChan);

if toggleEMG
   emgLines = initializeEMGPlot(ax_emg, numEMGChanToPlot);
end

%% Main loop to stream data at 50 Hz for plotting

forceStreamTime = tic; % Start timing plot update

while ishandle(fig)
   loopStartTime = tic; 
   try
       % ----------- Force data streaming -----------
       if serialObj.BytesAvailable > 0  % Only update wqhen new data arrives
           % Read force data only when available 
           fSample = fscanf(serialObj, '%f,%f,%f,%f'); % first channel is timestamp, the others are forces
           tStamps = [tStamps, fSample(1)];
           forceSample = fSample(2:4);

           % Step 1: Apply reverse states if needed, and also check whether all channels should be reversed (for extension positive)
           for i = 1:numForceChan
               if reverseStates(i)
                   forceSample(i) = -forceSample(i);
               end
           end

           if forceSignCheckbox.Value == 1
               forceSample = -forceSample;
               set(forceSignLabel, 'String', sprintf('%s\n%s','(+): Extension', '(-): Flexion '));
           else
               set(forceSignLabel, 'String', sprintf('%s\n%s','(+): Flexion', '(-): Extension '));
           end

           % Step 2: Apply zero values and calibration factors (calibrate the data)
           calibratedForce = (forceSample(1:numForceChan)' - zeroValues(1:numForceChan)) ./ calibrationFactors(1:numForceChan) * 100;

           % Step 3: Store the calibrated force data in forceData
           currentForceIndex = currentForceIndex + 1;
           if currentForceIndex > maxForceSamples
               currentForceIndex = 1; % Wrap around if exceeding preallocated size
           end  
           forceData(currentForceIndex, :) = calibratedForce; % Store calibrated data

           % Step 4a: Detect and replace spikes
           spikeThreshold = 20; % Define a threshold for spikes
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

           % Step 6: Update the plot with new data
           
           updateForcePlot_v10(ax_f, forceLines, forceData, fs_force, numForceChan, displayTime, bufferTime, forceTarget, forceMin, currentForceIndex);
           forceTimes = [forceTimes, toc(forceStreamTime)];
       else
           pause(0.0001); % Small pause to prevent busy waiting
       end
       
       % Handle zeroing
       if btnZero.Value
           zeroValues = forceSample(1:numForceChan)'; % Update zero values
           btnZero.Value = false;
           zeroed = 1;
       end

%         if strcmp(get(btnZero, 'Enable'), 'off')  % If button is pressed
%             zeroValues = forceSample(2:4)'; % Update zero values
%             set(btnZero, 'Enable', 'on');  % Reset the button state to enabled
%             zeroed = 1;
%         end

        % Handle Force Tracking Recording (similar code as before)
        if btnRecordTracking.Value && ~recordingTracking

            % Change the axes background color to light green
            ax_f.Color = [0.9, 1, 0.9];  % Light green color [R, G, B]
            
            recordStartForce = currentForceIndex+1;  % Start index of force data in next time step
            recordStartEMG = currentEMGIndex+1; 

            % Get the trapezium parameters from the input boxes
            tWait = str2double(tWaitBox.String);  % Can still use tWait for the final flat section. Note that it should ideally match the buffer time
            tSlope = str2double(tSlopeBox.String);
            tPlateau = str2double(tPlateauBox.String);
            forceTarget = str2double(forceTargetBox.String);

            % Get the selected trace type
            traceType = traceTypeDropdown.String{traceTypeDropdown.Value};
        
            % Generate the force trace depending on selection
            if strcmp(traceType, 'Trapezium')
                [tTrace, fTrace] = force_trace_trapezium(tPlateau, tSlope, tWait, forceTarget, fs_force);
            elseif strcmp(traceType, 'Triangular')
                [tTrace, fTrace] = force_trace_triang(fs_force);
                forceTarget = 30; % these are use to adjust Y axis limits
                forceMin = -30;
            end
            
            % Add buffer time to the start time to make it appear from the far right
            currentTime = currentForceIndex/fs_force;
            tTrace = tTrace + currentTime;  % Start at the far right of the plot
        
            % Compute the total duration of the trapezium (ignoring tWait for the start)
            if strcmp(traceType, 'Trapezium')
                traceDuration = 2*tWait + 2*tSlope + tPlateau;
            elseif strcmp(traceType, 'Triangular')
                traceDuration = 25;
            end
%             traceDuration = 2*tWait + 2*tSlope + tPlateau;
        
            % Start tracking the trapezium
            recordingTracking = true;
            traceStartTime = currentTime;

            % Create a new animated line for the force trace
            forceTraceLine = animatedline(ax_f, 'Color', 'k', 'LineWidth', 1, 'LineStyle', '-');
            lastPlottedIdx = 1;  % Initialize index for progressive plotting
        end
        
        % Update the trapezium trace if it's being tracked
        if recordingTracking
            currentTime = currentForceIndex/fs_force;  % Current time in the streaming data
        
            % Check if we're still within the trapezium duration
            if currentTime <= (traceStartTime + traceDuration)
                % Determine the new points to plot based on the current time
                validIdx = find(tTrace <= currentTime + bufferTime, 1, 'last');  % Plot based on the visible portion
        
                if ~isempty(validIdx) && validIdx > lastPlottedIdx
                    % Add only the new points to the animated line
                    addpoints(forceTraceLine, tTrace(lastPlottedIdx:validIdx), fTrace(lastPlottedIdx:validIdx));
                    lastPlottedIdx = validIdx;  % Update last plotted index
                end
        
                % Adjust the x-axis range to move the force trace from right to left
                % Keep the x-axis shifting as the trapezium progresses
                xlim(ax_f, [currentTime - displayTime, currentTime + bufferTime]);
        
            else
                % Stop tracking once the force trace is done
                recordingTracking = false;
                btnRecordTracking.Value = false;
                
                recordEndForce = currentForceIndex-1;  % End index of force data in last time step

                if toggleEMG
                    recordEndEMG = currentEMGIndex- size(emgSample, 2);
                end
                
                % Get the participant ID, trial, and session values
               participantID = participantIDBox.String;
               trial = str2double(trialBox.String);
               session = str2double(sessionBox.String);
    
               % Get force target from the textbox and channel from the dropdown menu
               forceTarget = str2double(forceTargetBox.String);
               digit = forceChanDropdown.Value; % gets either 1, 2 or 3 depending of the option selected (we listed them in order)
    
               % Validate inputs
               if isempty(participantID)
                   disp('Error: Participant ID is required.');
               elseif isnan(trial) || isnan(session)
                   disp('Error: Trial and Session must be integer values.');
               else
                   % Construct the filename
                   filename = sprintf('S%s_ss%d_dig%d_f%d_t%d.mat', participantID, session, digit, forceTarget, trial);
               end

                % Get the cropped data for force and EMG and save results
                recordedForce = forceData(recordStartForce:recordEndForce, :);
                if toggleEMG
                    recordedEMG = emgData(:, recordStartEMG:recordEndEMG); % Adjust indexing for EMG as needed
                    % Save the data
                    save(filename, 'emgData', 'forceData', 'recordedEMG', 'recordedForce', 'recordStartForce', 'recordEndForce', 'recordStartEMG','recordEndEMG');
                else
                    save(filename, 'forceData', 'recordedForce', 'recordStartForce', 'recordEndForce');
                end

                disp(['Recording saved as: ', filename]);

                % Reset other variables
                forceTarget = 100; % reset force target and min as well as the Y axis limits
                forceMin = 0;
                % Revert the axes background color to default (usually white)
                ax_f.Color = [1, 1, 1];  % White color [R, G, B]
            end
        end

        % ----------- EMG Data Streaming -----------
        if toggleEMG
            emgTimeStart = tic;  % Start timing EMG data streaming
            emgSample = streamEMGData(tcpSocket, NumEMGChanSessn, blockData, TotNumByte, PlotTime, DeviceEN, EMG, NumChan, fs_emg);

            % Update emgData at the current index
            currentEMGIndex = currentEMGIndex + size(emgSample, 2);  % Increase by the number of samples in this block
            if currentEMGIndex > maxEMGSamples
                currentEMGIndex = 1;  % Wrap around if exceeding preallocated size
            end
            emgData(:, currentEMGIndex - size(emgSample, 2) + 1:currentEMGIndex) = emgSample;

            % Update the EMG plot
            currentTime = currentEMGIndex / fs_emg;
            updateEMGPlot_v4(emgLines, ax_emg, emgSample, OffsetEMG, currentTime, NumEMGChanSessn, displayTime, numEMGChanToPlot);
%             updateEMGPlot_v5(emgLines, ax_emg, emgSample, OffsetEMG, currentTime, numEMGChannels, displayTime, numEMGChanToPlot)
            emgTimes = [emgTimes, toc(emgTimeStart)];  % Store elapsed time for EMG
        end


       % Handle manual recording
       if btnRecord.Value && ~recording
           recording = true;
           recordStartForce = currentForceIndex; % Start index of force data
       elseif ~btnRecord.Value && recording
           recording = false;
           recordEndForce = currentForceIndex; % End index of force data

           % Get the participant ID, trial, and session values
           participantID = participantIDBox.String;
           trial = str2double(trialBox.String);
           session = str2double(sessionBox.String);

           % Get force target from the textbox
           forceTarget = str2double(forceTargetBox.String);

           % Validate inputs
           if isempty(participantID)
               disp('Error: Participant ID is required.');
           elseif isnan(trial) || isnan(session)
               disp('Error: Trial and Session must be integer values.');
           else
               % Construct the filename
               filename = sprintf('S%s_ss%d_f%d_t%d.mat', participantID, session, forceTarget, trial);

               % Get the cropped data for force and EMG
               recordedForce = forceData(recordStartForce:recordEndForce, :);
               recordedEMG = emgData(:, recordStartForce:recordEndForce); % Adjust indexing for EMG as needed

               % Save the data
               save(filename, 'emgData', 'forceData', 'recordedEMG', 'recordedForce', 'recordStartForce', 'recordEndForce');
               disp(['Recording saved as: ', filename]);
           end
       end

       % Check if the close button is pressed
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
   end

   drawnow;

   elapsedExecTimes = [elapsedExecTimes, toc(loopStartTime)];
end

% If the figure was closed without cleaning resources
if ~ishandle(fig)
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
end

