function updateEMGPlot_v5(emgLines, ax, emgData, OffsetEMG, currentTime, numEMGChannels, displayTime, numEMGChanToPlot)
    % Limit the number of EMG channels to plot
    channelsToPlot = min(numEMGChannels, numEMGChanToPlot);
    
    % Calculate time vector
    time = (0:size(emgData,2)-1) / fs_emg;
    
    % Extract the time range for the last 'displayTime' seconds
    maxSamples = displayTime * fs_emg;
    if size(emgData,2) > maxSamples
        dataToPlot = emgData(:, end-maxSamples+1:end);
        timeToPlot = time(end-maxSamples+1:end);
    else
        dataToPlot = emgData;
        timeToPlot = time;
    end
    
    % Update animatedline with new EMG data
    for i = 1:channelsToPlot
        clearpoints(emgLines(i));  % Clear previous points
        addpoints(emgLines(i), timeToPlot, dataToPlot(i,:) + OffsetEMG * (i - 1));
    end

    % Adjust axis limits to show the last 'displayTime' seconds of data, with 5 seconds of extra space
    xlim(ax, [max(0, currentTime - displayTime), currentTime + 5]);
end