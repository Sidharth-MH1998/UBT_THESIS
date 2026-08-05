function updateEMGPlot_v2(ax, data, OffsetEMG, numEMGChannels, fs_emg, displayTime)
    time = (0:length(data)-1) / fs_emg;
    offset = OffsetEMG * (0:numEMGChannels-1)';
    maxSamples = displayTime * fs_emg;

    if length(time) > maxSamples
        dataToPlot = data(:, end-maxSamples+1:end);
        timeToPlot = time(end-maxSamples+1:end);
    else
        dataToPlot = data;
        timeToPlot = time;
    end

    plot(ax, timeToPlot, dataToPlot + offset);
    ylim(ax, [-OffsetEMG OffsetEMG*numEMGChannels]);
    
    % Set the x-axis limits for a 15-second window
    if timeToPlot(end) > displayTime
        xlim(ax, [timeToPlot(end)-displayTime, timeToPlot(end)]);
    else
        xlim(ax, [0 displayTime]);
    end
end
