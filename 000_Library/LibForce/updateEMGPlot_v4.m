function updateEMGPlot_v4(emgLines, ax, emgSample, OffsetEMG, currentTime, numEMGChannels, displayTime, numEMGChanToPlot)
    % Limit the number of EMG channels to plot
    channelsToPlot = min(numEMGChannels, numEMGChanToPlot);  % Plot at most numEMGChanToPlot channels

    % Update animatedline with new EMG data
    for i = 1:channelsToPlot
        addpoints(emgLines(i), currentTime, emgSample(i) + OffsetEMG * (i - 1));
    end

    % Adjust axis limits to show the last 10 seconds of data, with 5 seconds of extra space
    xlim(ax, [max(0, currentTime - (displayTime - 5)), currentTime + 5]);  % 10 sec data, 5 sec empty
end
