% RUN_NOVECENTO_LIVE
% Simple raw Novecento+ real-time EMG plot based on the OTB reference code.
% Close the plot window to stop streaming safely.

clear; clc;

%% Settings
useWiFi = false;
ethernetIP = '169.254.1.10';
wifiIP = '192.168.1.1';
tcpPort = 23456;

activeInput = 1;
plotChannels = 1:4:64;
updateIntervalSec = 1;
displayWindowSec = 2;

% OTB Novecento configuration codes.
mode = 0;
gain = 1;
highResolution = 1;
hardwareHighPass = 1;
samplingCode = 1; % 0=500 Hz, 1=2000 Hz, 2=4000 Hz, 3=8000 Hz

samplingValues = [500 2000 4000 8000];
channelCountByProbe = [0 14 22 38 46 70 102 0 0 0 0 0 0 0 0 0];
auxRowsByRate = [16 64 128 256];
auxRateSelection = 2;
gainFactor = 0.2861; % OTB reference conversion to mV

%% Build Novecento configuration command
inputActive = zeros(10, 1);
inputActive(activeInput) = [1];

configCommand = zeros(1, 15, 'uint8');
auxRateCodes = [0 16 32 48];
configCommand(1) = uint8(128 + auxRateCodes(auxRateSelection));
configCommand(2) = uint8(2^(activeInput - 1));
configCommand(4) = uint8(1);
configCommand(4 + activeInput) = uint8( ...
    mode * 64 + gain * 16 + hardwareHighPass * 8 + ...
    highResolution * 4 + samplingCode);
configCommand(15) = uint8(CRC8(double(configCommand), 14));

%% Connect and request probe information
if useWiFi
    deviceIP = wifiIP;
else
    deviceIP = ethernetIP;
end

socket = tcpclient(deviceIP, tcpPort, ...
    'ByteOrder', 'little-endian', 'Timeout', 100);
cleanupObject = onCleanup(@() stop_novecento(socket, configCommand)); %#ok<NASGU>

probeRequest = uint8([1 0]);
probeRequest(2) = uint8(CRC8(double(probeRequest(1)), 1));
write(socket, probeRequest, 'uint8');
settings = read(socket, 20, 'uint8')';

probeType = double(settings(activeInput + 1));
numberOfChannels = channelCountByProbe(probeType + 1);
if numberOfChannels == 0
    error('No supported probe was detected on input %d.', activeInput);
end

write(socket, configCommand, 'uint8');

fs = samplingValues(samplingCode + 1);
inputRows = (highResolution + 1) * fs / 500 * numberOfChannels;
packetRows = inputRows + auxRowsByRate(auxRateSelection) + 128;
baseColumnsPerBlock = round(updateIntervalSec * 500);
valuesPerBlock = packetRows * baseColumnsPerBlock;

plotChannels = plotChannels(plotChannels >= 1 & plotChannels <= numberOfChannels);
if isempty(plotChannels)
    error('No valid channels selected in plotChannels.');
end

%% Prepare real-time plot
figureHandle = figure('Name', 'Novecento+ Raw EMG', 'Color', 'w');
axesHandle = axes('Parent', figureHandle);
hold(axesHandle, 'on');

displaySamples = round(fs * displayWindowSec);
timeSec = (0:(displaySamples - 1)) / fs;
displayBuffer = nan(numel(plotChannels), displaySamples);
elapsedTimeSec = 0;
lines = gobjects(1, numel(plotChannels));
for index = 1:numel(plotChannels)
    lines(index) = plot(axesHandle, timeSec, ...
        plotChannels(index) * ones(size(timeSec)), 'LineWidth', 0.8);
end

hold(axesHandle, 'off');
grid(axesHandle, 'on');
xlabel(axesHandle, 'Time (s)');
ylabel(axesHandle, 'Channel');
title(axesHandle, 'Novecento+ Raw EMG');
xlim(axesHandle, [0 displayWindowSec]);
yticks(axesHandle, plotChannels);
ylim(axesHandle, [min(plotChannels) - 1, max(plotChannels) + 1]);

fprintf('Connected to %s | Input %d | %d channels | %.0f Hz\n', ...
    deviceIP, activeInput, numberOfChannels, fs);
fprintf('Close the plot window to stop.\n');

%% Read and plot raw EMG
while ishandle(figureHandle)
    rawValues = read(socket, valuesPerBlock, 'int16')';
    packet = reshape(rawValues, packetRows, baseColumnsPerBlock);
    inputValues = reshape(packet(1:inputRows, :), 1, []);

    if highResolution == 1
        inputValues = typecast(inputValues, 'int32');
    end

    emg = gainFactor * double(reshape(inputValues, numberOfChannels, []));

    % 50 Hz notch filter
    %[bNotch, aNotch] = butter(2, [49 51] / (fs / 2), 'stop');
    %emg = (bNotch, aNotch, emg')';



    newBlock = emg(plotChannels, :);
    displayBuffer = [displayBuffer(:, size(newBlock, 2) + 1:end), newBlock];
    elapsedTimeSec = elapsedTimeSec + size(newBlock, 2) / fs;
    windowStartSec = max(0, elapsedTimeSec - displayWindowSec);
    timeSec = windowStartSec + (0:(displaySamples - 1)) / fs;

    displayBlock = displayBuffer - median(displayBuffer, 2, 'omitnan');
    channelScale = std(displayBlock, 0, 2, 'omitnan');
    channelScale(channelScale < eps) = 1;
    displayBlock = 0.35 * displayBlock ./ channelScale;
    displayBlock = max(min(displayBlock, 0.45), -0.45);

    for index = 1:numel(plotChannels)
        lines(index).XData = timeSec;
        lines(index).YData = displayBlock(index, :) + plotChannels(index);
    end

    xlim(axesHandle, [windowStartSec, max(displayWindowSec, elapsedTimeSec)]);
    title(axesHandle, sprintf('Novecento+ Raw EMG | %.1f s elapsed', elapsedTimeSec));
    drawnow limitrate;
end

function stop_novecento(socket, configCommand)

try
    stopCommand = configCommand;
    stopCommand(1) = uint8(0);
    stopCommand(15) = uint8(CRC8(double(stopCommand), 14));
    write(socket, stopCommand, 'uint8');
    pause(0.5);
catch
end

end
