%% EMG quality check
% Load an EMG matrix (channels x samples) into emgData before running this script.
% Outputs left in the workspace:
%   filteredEMG, badchan, badChannelReport
close all

%% User settings
emgData = recordedEMG;
forceData = recordedForce(:,2); % second recorded-force channel
samplingRate = 2000;       % Hz
forceSamplingRate = 50;    % Hz
channelsToPlot = 1:4:64;     % [] plots every channel
spectrumChannel = 1;       % channel used for the frequency-spectrum plot
visibleWindowSec = Inf;    % Inf plots the complete recording
lineFrequencyHz = 50;      % used by bad-channel detection

useAdaptiveNotch = true;   % calls adaptiveNotchFilter.m from the path
baseFreqRange = [45 55];
numHarmonics = 9;
notchWidth = 1;            % Hz
useBandpass = true;

%% Validate input and settings

forceData = forceData(:);
[numberOfChannels, numberOfSamples] = size(emgData);

if isempty(channelsToPlot)
    channelsToPlot = 1:numberOfChannels;
end

plotSamples = numberOfSamples;

if isfinite(visibleWindowSec)
    if visibleWindowSec <= 0
        error('visibleWindowSec must be positive or Inf.');
    end
    plotSamples = min(numberOfSamples, max(1, round(visibleWindowSec * samplingRate)));
end
fprintf('EMG data is loaded \n');
fprintf(' %d channels, %d samples, %.3f seconds at %.1f Hz.\n', ...
    numberOfChannels, numberOfSamples, numberOfSamples / samplingRate, samplingRate);

%% Filter the complete EMG matrix
filteredEMG = double(emgData);
if useAdaptiveNotch
   filteredEMG = adaptiveNotchFilter(filteredEMG, samplingRate,baseFreqRange, numHarmonics, notchWidth);
end

if useBandpass
   filteredEMG = bandpassingals(filteredEMG, samplingRate, 1); % surface EMG
end

%% Plot selected channels before and after filtering
localPlotStackedComparison(double(emgData(channelsToPlot, 1:plotSamples)), ...
    filteredEMG(channelsToPlot, 1:plotSamples),channelsToPlot, samplingRate);

%% Plot force
forcePlotSamples = size(forceData, 1);
if isfinite(visibleWindowSec)
    forcePlotSamples = min(forcePlotSamples, ...
        max(1, round(visibleWindowSec * forceSamplingRate)));
end
localPlotForce(forceData(1:forcePlotSamples), forceSamplingRate);

%% Plot the selected channel's spectrum before and after filtering
localPlotSpectrum(double(emgData(spectrumChannel, :)), filteredEMG(spectrumChannel, :), samplingRate, spectrumChannel);

%% Identify and print potential bad channels
[badchan, badChannelReport] = FindBadchan(filteredEMG, samplingRate, lineFrequencyHz);

%% Local plotting functions
function localPlotForce(forceSignal, fsamp)
timeSec = (0:numel(forceSignal)-1) / fsamp;
figure('Name', 'Force - recordedForce channel 2', 'Color', 'w');
plot(timeSec, forceSignal, 'LineWidth', 1);
grid on;
xlabel('Time (s)');
ylabel('Force');
title('Force - recordedForce(:,2)');
xlim([0 max(timeSec(end), 1/fsamp)]);
end

function localPlotStackedComparison(rawSignal, filteredSignal,channelNumbers, fsamp)
% Display raw and filtered channels side by side with identical scaling.
combinedSignal = [rawSignal filteredSignal];
channelScale = std(combinedSignal, 0, 2);
channelScale = channelScale(isfinite(channelScale) & channelScale > 0);
if isempty(channelScale)
    offset = 1;
else
    offset = max(6 * median(channelScale), eps);
end

figure('Name', 'EMG Visualisation', 'Color', 'w');
layout = tiledlayout(1, 2, 'TileSpacing', 'compact', ...
    'Padding', 'compact');
rawAxes = nexttile(layout);
localDrawStacked(rawAxes, rawSignal, channelNumbers, fsamp, offset, ...
    'Before');
filteredAxes = nexttile(layout);
localDrawStacked(filteredAxes, filteredSignal, channelNumbers, fsamp, ...
    offset, 'After');
linkaxes([rawAxes filteredAxes], 'xy');
title(layout, 'EMG quality comparison');
end

function localDrawStacked(ax, signal, channelNumbers, fsamp, offset, plotTitle)
timeSec = (0:size(signal, 2)-1) / fsamp;
hold(ax, 'on');
for index = 1:size(signal, 1)
    plot(ax, timeSec, signal(index, :) + offset * (index - 1), ...
        'LineWidth', 0.75);
end
hold(ax, 'off');
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Channel');
title(ax, plotTitle);
yticks(ax, offset * (0:numel(channelNumbers)-1));
yticklabels(ax, string(channelNumbers));
xlim(ax, [0 max(timeSec(end), 1/fsamp)]);
ylim(ax, [-offset, offset * numel(channelNumbers)]);
end

function localPlotSpectrum(rawSignal, filteredSignal, fsamp, channelNumber)
rawSignal = rawSignal - mean(rawSignal);
filteredSignal = filteredSignal - mean(filteredSignal);
windowLength = min(numel(rawSignal), max(8, round(fsamp)));
window = hann(windowLength, 'periodic');
overlap = floor(windowLength / 2);
nfft = max(2048, 2^nextpow2(windowLength));
[rawPower, frequencyHz] = pwelch(rawSignal, window, overlap, nfft, fsamp);
filteredPower = pwelch(filteredSignal, window, overlap, nfft, fsamp);

figure('Name', sprintf('EMG spectrum - channel %d', channelNumber), ...
    'Color', 'w');
plot(frequencyHz, 10*log10(rawPower + eps), 'DisplayName', 'Before');
hold on;
plot(frequencyHz, 10*log10(filteredPower + eps), 'DisplayName', 'After');
hold off;
grid on;
xlim([0 min(700, fsamp/2)]);
xlabel('Frequency (Hz)');
ylabel('Power (dB/Hz)');
title(sprintf('EMG frequency spectrum at Channel %d', ...
    channelNumber));
legend('Location', 'best');
end
