%% Filter and visualise recorded EMG channels
% Put your EMG matrix in emgData. It must be channels x samples.
% Example:
%   emgData = trimmedEMG;
%   emgData = recordedEMG;

emgData = emgValues;
samplingRate = 2000;

channelsToPlot = 1:16;  % [] plots all channels
visibleWindowSec = Inf; % Inf plots full recording. Example: 10 plots first 10 sec.

%% Filter parameters
useAdaptiveNotch = true;
baseFreqRange = [45 55];
numHarmonics = 9;
notchWidth = 1;

useBandpass = true;
emgtype = 1; % 1 = surface EMG, 2 = intra-muscular EMG

%% Validate and select channels
[numberOfChannels, numberOfSamples] = size(emgData);
recordingTimeSec = numberOfSamples / samplingRate;

if isempty(channelsToPlot)
    channelsToPlot = 1:numberOfChannels;
end

channelsToPlot = channelsToPlot(channelsToPlot >= 1 & channelsToPlot <= numberOfChannels);
if isempty(channelsToPlot)
    error('No valid channels selected in channelsToPlot.');
end

plotSamples = numberOfSamples;
if isfinite(visibleWindowSec)
    plotSamples = min(numberOfSamples, round(visibleWindowSec * samplingRate));
end

fprintf('Number of channels: %d\n', numberOfChannels);
fprintf('Number of samples: %d\n', numberOfSamples);
fprintf('Recording time: %.3f seconds\n', recordingTimeSec);
fprintf('Plotting %d channel(s): %s\n', numel(channelsToPlot), mat2str(channelsToPlot));

%% Filter full EMG
filteredEMG = double(emgData);

if useAdaptiveNotch
    filteredEMG = adaptiveNotchFilter(filteredEMG, samplingRate, ...
        baseFreqRange, numHarmonics, notchWidth);
end

if useBandpass
    filteredEMG = bandpassingals(filteredEMG, samplingRate, emgtype);
end

%% Plot before and after separately
plot_stacked_emg( ...
    double(emgData(channelsToPlot, 1:plotSamples)), ...
    channelsToPlot, samplingRate, 'Before filtering');

plot_stacked_emg( ...
    double(filteredEMG(channelsToPlot, 1:plotSamples)), ...
    channelsToPlot, samplingRate, 'After adaptive notch + band-pass filtering');

%% Local plotting helper
function plot_stacked_emg(plotEmg, channelsToPlot, samplingRate, plotTitle)

timeSec = (0:(size(plotEmg, 2) - 1)) / samplingRate;

figure('Name', plotTitle, 'Color', 'w');
ax = axes;
hold(ax, 'on');

offset = max(max(std(plotEmg, 0, 2) * 6), 1);

for ii = 1:size(plotEmg, 1)
    plot(ax, timeSec, plotEmg(ii, :) + offset * (ii - 1), 'LineWidth', 1);
end

hold(ax, 'off');
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Channel');
title(ax, plotTitle);

yticks(ax, offset * (0:(numel(channelsToPlot) - 1)));
yticklabels(ax, cellstr(num2str(channelsToPlot(:))));
xlim(ax, [timeSec(1) max(timeSec(end), 1 / samplingRate)]);
ylim(ax, [-offset offset * numel(channelsToPlot)]);

end

%% Adaptive notch filter
function filteredSignal = adaptiveNotchFilter(signal, fsamp, baseFreqRange, numHarmonics, notchWidth)

if nargin < 3
    baseFreqRange = [45, 55];
end
if nargin < 4
    numHarmonics = 9;
end
if nargin < 5
    notchWidth = 1;
end

[numChannels, signalLength] = size(signal);
filteredSignal = zeros(size(signal));

for channel = 1:numChannels
    signalFFT = fft(signal(channel, :));
    freqAxis = (0:signalLength-1) * fsamp / signalLength;

    baseFreqRange_idx = find(freqAxis >= baseFreqRange(1) & freqAxis <= baseFreqRange(2));
    [~, maxIdx] = max(abs(signalFFT(baseFreqRange_idx)));
    baseFreq = freqAxis(baseFreqRange_idx(maxIdx));

    for harmonic = 1:numHarmonics
        notchFreq = harmonic * baseFreq;
        if notchFreq >= fsamp / 2
            break;
        end

        [b, a] = designNotchFilter(notchFreq, notchWidth, fsamp);
        signal(channel, :) = filtfilt(b, a, signal(channel, :));
    end

    filteredSignal(channel, :) = signal(channel, :);
end

end

function [b, a] = designNotchFilter(notchFreq, notchWidth, fsamp)

wo = 2*pi*notchFreq/fsamp;
bw = 2*pi*notchWidth/fsamp;

r = 1 - bw/2;

b = [1 -2*cos(wo) 1];
a = [1 -2*r*cos(wo) r^2];

end

%% Band-pass filter
function filteredsignal = bandpassingals(signal, fsamp, emgtype)

if emgtype == 1
    [b, a] = butter(2, [20 500] / (fsamp / 2));
    filteredsignal = filtfilt(b, a, signal.').';
else
    [b, a] = butter(3, [100 4400] / (fsamp / 2));
    filteredsignal = filtfilt(b, a, signal.').';
end

end
