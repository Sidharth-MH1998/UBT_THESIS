function updateEMGPlot_v3(emgLines, ax, emgSample, OffsetEMG, currentTime, numEMGChannels, displayTime)
    % Update animatedline with new EMG data
    for i = 1:numEMGChannels
        addpoints(emgLines(i), currentTime, emgSample(i) + OffsetEMG * (i - 1));
    end

    % Adjust axis limits to show the last 15 seconds of data
    xlim(ax, [max(0, currentTime - displayTime), currentTime]);
end
