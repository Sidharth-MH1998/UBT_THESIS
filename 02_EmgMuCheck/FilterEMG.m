%% Preprocess and visualise recorded EMG channels
% Uses the Muedit filters .
% The EMG matrix must be channels x samples.

emgData = trimmedEMG;
samplingRate = 2000;

channelsToPlot = 1:16;  % [] plots all channels
visibleWindowSec = Inf; % Inf plots the full recording

%% preprocessing parameters
useAdaptiveNotch = true;
baseFreqRange = [45 55];
numHarmonics = 9;
notchWidth = 1;

useBandpass = true;
emgtype = 1; % 1 = surface EMG, 2 = intramuscular EMG



%% Validate and select channels
if ~isnumeric(emgData) || ~ismatrix(emgData) || isempty(emgData)
    error('emgData must be a non-empty numeric channels-by-samples matrix.');
end
if ~isscalar(samplingRate) || ~isfinite(samplingRate) || samplingRate <= 0
    error('samplingRate must be a positive finite scalar.');
end

[numberOfChannels, numberOfSamples] = size(emgData);
recordingTimeSec = numberOfSamples / samplingRate;

if isempty(channelsToPlot)
    channelsToPlot = 1:numberOfChannels;
end

channelsToPlot = channelsToPlot( ...
    channelsToPlot >= 1 & channelsToPlot <= numberOfChannels);
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
fprintf('Plotting %d channel(s): %s\n', ...
    numel(channelsToPlot), mat2str(channelsToPlot));

%% Filter the full EMG
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
    channelsToPlot, samplingRate, ...
    'After adaptive notch + band-pass filtering');

%% Local plotting helper
function plot_stacked_emg(plotEmg, channelsToPlot, samplingRate, plotTitle)

timeSec = (0:(size(plotEmg, 2) - 1)) / samplingRate;

figure('Name', plotTitle, 'Color', 'w');
ax = axes;
hold(ax, 'on');

offset = max(max(std(plotEmg, 0, 2) * 6), 1);

for ii = 1:size(plotEmg, 1)
    plot(ax, timeSec, plotEmg(ii, :) + offset * (ii - 1), ...
        'LineWidth', 1);
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
