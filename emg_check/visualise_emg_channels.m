%% Visualise recorded EMG channels

emgData = recordedEMG ;        % Put your EMG matrix here, e.g. emgData = recordedEMG;
samplingRate = 2000;  % Put your sampling rate here in Hz

channelsToPlot =[1:64];%[1 8 16 24 32 40 48 56 64 72 80 88 96 104 112 120 ];  % [] plots all channels. Example: [1 2 3 10]
visibleWindowSec = Inf; % Inf plots full recording. Example: 10 plots first 10 sec.


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

plotEmg = double(emgData(channelsToPlot, 1:plotSamples));
timeSec = (0:(plotSamples - 1)) / samplingRate;

fprintf('Number of channels: %d\n', numberOfChannels);
fprintf('Number of samples: %d\n', numberOfSamples);
fprintf('Recording time: %.3f seconds\n', recordingTimeSec);
fprintf('Plotting %d channel(s): %s\n', numel(channelsToPlot), mat2str(channelsToPlot));

%% stacked plot
figure('Name', 'Recorded EMG channels', 'Color', 'w');
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
title(ax, 'Recorded EMG - stacked channels');

yticks(ax, offset * (0:(numel(channelsToPlot) - 1)));
yticklabels(ax, cellstr(num2str(channelsToPlot(:))));
xlim(ax, [timeSec(1) max(timeSec(end), 1 / samplingRate)]);
ylim(ax, [-offset offset * numel(channelsToPlot)]);
