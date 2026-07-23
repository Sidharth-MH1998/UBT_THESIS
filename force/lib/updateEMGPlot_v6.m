function updateEMGPlot_v6(emgLines, ax_emg, emgData, OffsetEMG, currentTime, numEMGChannels, displayTime, numEMGChanToPlot, lastPlottedIdx)
    % Limit the number of EMG channels to plot
    channelsToPlot = min(numEMGChannels, numEMGChanToPlot);

    % Calculate time vector
    time = (0:size(emgData, 2) - 1) / fs_emg;

    % Extract the time range for the last 'displayTime' seconds
    maxSamples = displayTime * fs_emg;
    if size(emgData, 2) > maxSamples
        newData = emgData(:, end - maxSamples + 1:end);
        newTime = time(end - maxSamples + 1:end);
    else
        newData = emgData;
        newTime = time;
    end
    
    % Plot only the new points since the last plotted index
    if lastPlottedIdx < size(emgData, 2)
        newIdxRange = lastPlottedIdx+1:size(emgData, 2);
        newTimeRange = (newIdxRange - 1) / fs_emg;
        
        for i = 1:channelsToPlot
            % Add only new points to the animated line
            addpoints(emgLines(i), newTimeRange, emgData(i, newIdxRange) + OffsetEMG * (i - 1));
        end
    end

    % Adjust axis limits to show the last 'displayTime' seconds of data, with 5 seconds of extra space
    xlim(ax_emg, [max(0, currentTime - displayTime), currentTime + 5]);
end
