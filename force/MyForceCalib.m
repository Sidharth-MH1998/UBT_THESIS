clc;
close all;
clearvars;

% Force-only calibration script for 3 load cells.
% This keeps the v5 calibration workflow, removes EMG, and reduces plot lag.

%% Parameters
defaultParticipantID = "rm";
ard_port = "COM4";
fs_force = 50;
numForceChan = 3;
displayTime = 10;
plotUpdateRate = 10;
calibrationTime = 15;
zeroTime = 3;
maxDuration = 10 * 60;

maxForceSamples = fs_force * maxDuration;
plotUpdateInterval = max(1, round(fs_force / plotUpdateRate));

forceData = zeros(maxForceSamples, numForceChan);
rawForce = zeros(maxForceSamples, numForceChan);
timeStamps = zeros(maxForceSamples, 1);
currentForceIndex = 0;

defaultCalibrationFactors = [1e6, 0.8e6, 0.8e6];
defaultZeroValues = [-400, 150, 750];
defaultReverseStates = [false, true, false];

calibrationFile = "S" + defaultParticipantID + "_calibrationData.mat";
if isfile(calibrationFile)
    loadedCalibration = load(calibrationFile, "calibrationFactors", "zeroValues", "reverseStates");
    calibrationFactors = loadedCalibration.calibrationFactors;
    zeroValues = loadedCalibration.zeroValues;
    reverseStates = loadedCalibration.reverseStates;
else
    calibrationFactors = defaultCalibrationFactors;
    zeroValues = defaultZeroValues;
    reverseStates = defaultReverseStates;
end

tempCalibrationFactors = calibrationFactors;
tempZeroValues = zeroValues;

[fig, ax_f, ui] = setupFigureForForceCalibration(numForceChan, defaultParticipantID, ...
    tempCalibrationFactors, reverseStates);

serialObj = initializeArduinoStream(ard_port);
cleanupObj = onCleanup(@() closeSerialObject(serialObj));

channelCalibData = initializeCalibrationData(numForceChan);
calibrationInProgress = false(1, numForceChan);
calibrationStartTime = zeros(1, numForceChan);

windowSize = 0.25;
fs_window = max(1, round(windowSize * fs_force));
alpha = 0.3;
spikeThreshold = 50;

forceLines = initializeForcePlot(ax_f, numForceChan);
lastStatusSecond = -inf(1, numForceChan);
lastReverseStates = reverseStates;

%% Main loop
while ishandle(fig)
    try
        if serialObj.NumBytesAvailable > 0
            line = readline(serialObj);
            fSample = sscanf(line, "%f,%f,%f,%f");

            if numel(fSample) >= 4
                nextForceIndex = currentForceIndex + 1;
                if nextForceIndex > maxForceSamples
                    nextForceIndex = 1;
                end

                timeStamps(nextForceIndex) = fSample(1);
                forceSample = fSample(2:4)';

                reverseStates = getReverseStates(ui.btnReverse);
                for i = 1:numForceChan
                    if reverseStates(i)
                        forceSample(i) = -forceSample(i);
                    end
                end

                currentForceIndex = nextForceIndex;
                rawForce(currentForceIndex, :) = forceSample;

                calibratedForce = (forceSample - tempZeroValues(1:numForceChan)) ...
                    ./ tempCalibrationFactors(1:numForceChan) * 100;

                if currentForceIndex > 1
                    previousForce = forceData(currentForceIndex - 1, :);
                    isSpike = abs(calibratedForce - previousForce) > spikeThreshold;
                    filteredForce = calibratedForce;
                    filteredForce(isSpike) = previousForce(isSpike);
                    filteredForce = alpha * filteredForce + (1 - alpha) * previousForce;
                else
                    filteredForce = calibratedForce;
                end

                forceData(currentForceIndex, :) = filteredForce;

                if mod(currentForceIndex, plotUpdateInterval) == 0
                    updateForcePlot(ax_f, forceLines, forceData, fs_force, numForceChan, ...
                        displayTime, currentForceIndex);
                end

                if any(reverseStates ~= lastReverseStates)
                    lastReverseStates = reverseStates;
                    ui.txtStatus.String = "Reverse states updated.";
                end

                [calibrationInProgress, calibrationStartTime, channelCalibData, ...
                    tempCalibrationFactors, lastStatusSecond] = handleCalibrationButtons( ...
                    ui, calibrationInProgress, calibrationStartTime, channelCalibData, ...
                    rawForce, currentForceIndex, fs_window, calibrationTime, ...
                    tempCalibrationFactors, lastStatusSecond);

                if ui.btnSaveZero.Value
                    if currentForceIndex >= zeroTime * fs_force
                        zeroStart = currentForceIndex - zeroTime * fs_force + 1;
                        zeroData = rawForce(zeroStart:currentForceIndex, :);
                        tempZeroValues = mean(zeroData, 1);
                        ui.txtStatus.String = "Zeroing complete.";
                    else
                        ui.txtStatus.String = "Not enough force data for zeroing yet.";
                    end
                    ui.btnSaveZero.Value = false;
                end

                if ui.btnSaveCalib.Value
                    participantID = string(strtrim(ui.participantIDBox.String));
                    if participantID == ""
                        ui.txtStatus.String = "Error: Please enter Participant ID.";
                    else
                        calibrationFile = "S" + participantID + "_calibrationData.mat";
                        calibrationFactors = tempCalibrationFactors;
                        zeroValues = tempZeroValues;
                        save(calibrationFile, "calibrationFactors", "zeroValues", ...
                            "reverseStates", "channelCalibData", "fs_force");
                        ui.txtStatus.String = "Calibration data saved: " + calibrationFile;
                    end
                    ui.btnSaveCalib.Value = false;
                end
            end
        else
            pause(0.001);
        end

        if ui.btnClose.Value
            break;
        end

    catch ME
        disp("Error occurred: " + ME.message);
        if ishandle(fig)
            ui.txtStatus.String = "Error: " + ME.message;
        end
    end

    drawnow limitrate;
end

if ishandle(fig)
    close(fig);
end

%% Local functions

function [fig, ax_f, ui] = setupFigureForForceCalibration(numForceChan, participantID, calibrationFactors, reverseStates)
    fig = figure("Name", "Force Calibration - 3 Load Cells", ...
        "NumberTitle", "off", ...
        "Position", [300, 300, 1600, 650], ...
        "Color", [0.94, 0.94, 0.94]);

    ax_f = axes("Parent", fig, "Units", "normalized", "Position", [0.06, 0.18, 0.67, 0.74]);
    hold(ax_f, "on");
    grid(ax_f, "on");
    title(ax_f, "Live Calibrated Force");
    xlabel(ax_f, "Time (s)");
    ylabel(ax_f, "Force (% calibrated)");

    controlPanel = uipanel(fig, "Title", "Calibration Controls", ...
        "Units", "normalized", "Position", [0.76, 0.08, 0.22, 0.84]);

    uicontrol(controlPanel, "Style", "text", "String", "Participant ID:", ...
        "Position", [10, 485, 100, 20]);
    ui.participantIDBox = uicontrol(controlPanel, "Style", "edit", ...
        "String", char(participantID), "Position", [120, 485, 100, 24]);

    ui.txtStatus = uicontrol(controlPanel, "Style", "text", "String", "Status: Ready", ...
        "Position", [10, 445, 320, 30], "HorizontalAlignment", "left");

    ui.btnCalibrate = gobjects(1, numForceChan);
    ui.txtCalibrate = gobjects(1, numForceChan);
    ui.btnReverse = gobjects(1, numForceChan);

    for i = 1:numForceChan
        y = 380 - (i - 1) * 80;
        uicontrol(controlPanel, "Style", "text", ...
            "String", "Calibrate Force " + string(i), ...
            "Position", [10, y + 30, 120, 20]);
        ui.txtCalibrate(i) = uicontrol(controlPanel, "Style", "text", ...
            "String", num2str(calibrationFactors(i)), ...
            "Position", [135, y + 30, 120, 20]);
        ui.btnCalibrate(i) = uicontrol(controlPanel, "Style", "togglebutton", ...
            "String", "Start", "Position", [260, y + 25, 70, 28]);

        ui.btnReverse(i) = uicontrol(controlPanel, "Style", "togglebutton", ...
            "String", "Reverse " + string(i), ...
            "Value", reverseStates(i), "Position", [10, y - 5, 100, 28]);
    end

    ui.btnSaveZero = uicontrol(controlPanel, "Style", "togglebutton", ...
        "String", "Save Zero", "Position", [10, 95, 100, 35]);

    ui.btnSaveCalib = uicontrol(controlPanel, "Style", "togglebutton", ...
        "String", "Save Calibration", "Position", [120, 95, 130, 35]);

    ui.btnClose = uicontrol(controlPanel, "Style", "togglebutton", ...
        "String", "Close", "Position", [10, 35, 100, 35], ...
        "BackgroundColor", [1, 0.4, 0.4]);
end

function serialObj = initializeArduinoStream(ard_port)
    serialObj = serialport(ard_port, 115200, "Timeout", 1);
    configureTerminator(serialObj, "LF");
    flush(serialObj);
    pause(1);
    disp("Arduino force stream connected on " + ard_port);
end

function channelCalibData = initializeCalibrationData(numForceChan)
    channelCalibData = struct();
    for i = 1:numForceChan
        channelCalibData(i).forceData = [];
        channelCalibData(i).forceIndexes = struct("start", [], "end", []);
    end
end

function reverseStates = getReverseStates(btnReverse)
    numForceChan = numel(btnReverse);
    reverseStates = false(1, numForceChan);
    for i = 1:numForceChan
        reverseStates(i) = logical(btnReverse(i).Value);
    end
end

function forceLines = initializeForcePlot(ax, numForceChan)
    colors = lines(numForceChan);
    forceLines = gobjects(1, numForceChan);
    for i = 1:numForceChan
        forceLines(i) = animatedline(ax, "Color", colors(i, :), "LineWidth", 1.5);
    end
    legend(ax, compose("Force %d", 1:numForceChan), "Location", "northwest");
end

function updateForcePlot(ax, forceLines, forceData, fs_force, numForceChan, displayTime, currentForceIndex)
    maxSamples = round(displayTime * fs_force);
    startIdx = max(1, currentForceIndex - maxSamples + 1);
    idx = startIdx:currentForceIndex;
    timeToPlot = idx / fs_force;

    for i = 1:numForceChan
        clearpoints(forceLines(i));
        addpoints(forceLines(i), timeToPlot, forceData(idx, i));
    end

    xlim(ax, [max(0, timeToPlot(end) - displayTime), timeToPlot(end) + 2]);
    ylim(ax, "auto");
end

function [calibrationInProgress, calibrationStartTime, channelCalibData, ...
    tempCalibrationFactors, lastStatusSecond] = handleCalibrationButtons( ...
    ui, calibrationInProgress, calibrationStartTime, channelCalibData, rawForce, ...
    currentForceIndex, fs_window, calibrationTime, tempCalibrationFactors, lastStatusSecond)

    numForceChan = numel(ui.btnCalibrate);

    for i = 1:numForceChan
        if ui.btnCalibrate(i).Value && ~calibrationInProgress(i)
            calibrationInProgress(i) = true;
            calibrationStartTime(i) = tic;
            channelCalibData(i).forceIndexes.start = currentForceIndex;
            ui.txtStatus.String = "Calibrating Force Channel " + string(i);
        end
    end

    for i = 1:numForceChan
        if calibrationInProgress(i)
            elapsedTime = toc(calibrationStartTime(i));
            remaining = max(0, calibrationTime - round(elapsedTime));

            if remaining ~= lastStatusSecond(i)
                ui.txtStatus.String = "Calibrating Force Channel " + string(i) + ...
                    "... " + string(remaining) + " s remaining";
                lastStatusSecond(i) = remaining;
            end

            if elapsedTime > calibrationTime
                calibrationInProgress(i) = false;
                ui.btnCalibrate(i).Value = false;
                channelCalibData(i).forceIndexes.end = currentForceIndex;

                idxStart = channelCalibData(i).forceIndexes.start;
                idxEnd = channelCalibData(i).forceIndexes.end;
                if idxStart < 1 || idxEnd < idxStart
                    ui.txtStatus.String = "Calibration failed for channel " + string(i);
                    continue
                end

                calibForceData = rawForce(idxStart:idxEnd, i);
                channelCalibData(i).forceData = calibForceData;
                movingAvg = movmean(calibForceData, fs_window);
                tempCalibrationFactors(i) = max(abs(movingAvg));
                ui.txtCalibrate(i).String = num2str(tempCalibrationFactors(i));
                ui.txtStatus.String = "Calibration complete for Force Channel " + string(i);
            end
        end
    end
end

function closeSerialObject(serialObj)
    if exist("serialObj", "var") && ~isempty(serialObj) && isvalid(serialObj)
        flush(serialObj);
        clear serialObj;
        disp("Arduino force stream closed.");
    end
end
