function updateEMGPlotWithLines(emgLines, ax, emgData, fs_emg, currentTime, numEMGChannels, displayTime, numEMGChanToPlot, OffsetEMG)
    % Limit the number of EMG channels to plot
    channelsToPlot = min(numEMGChannels, numEMGChanToPlot);  % Plot at most numEMGChanToPlot channels

    % Extract time and data for the last 'displayTime' seconds
    maxSamples = displayTime * fs_emg;
    time = (0:size(emgData, 2)-1) / fs_emg;  % Time vector based on sampling frequency
    if size(emgData, 2) > maxSamples
        dataToPlot = emgData(:, end-maxSamples+1:end);
        timeToPlot = time(end-maxSamples+1:end);
    else
        dataToPlot = emgData;
        timeToPlot = time;
    end

    % Update line objects with the new EMG data
    for i = 1:channelsToPlot
        set(emgLines(i), 'XData', timeToPlot, 'YData', dataToPlot(i,:) + OffsetEMG * (i - 1));
    end

    % Update x-axis limits dynamically to show the last 'displayTime' seconds plus buffer
    xlim(ax, [max(0, currentTime - displayTime), currentTime + 5]);  % Add 5-second buffer at the end
end