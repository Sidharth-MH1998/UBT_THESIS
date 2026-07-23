function updateForcePlot_v3(ax, data, fs_force, numForceChannels, displayTime, forcePlots)
    maxSamples = displayTime * fs_force;
    time = (0:size(data,1)-1) / fs_force;

    if size(data,1) > maxSamples
        dataToPlot = data(end-maxSamples+1:end, :);
        timeToPlot = time(end-maxSamples+1:end);
    else
        dataToPlot = data;
        timeToPlot = time;
    end

    % Instead of plotting again, update the existing plot lines
    set(forcePlots(1), 'XData', timeToPlot, 'YData', dataToPlot(:,1)); % Update Force 1
    if numForceChannels >= 2
        set(forcePlots(2), 'XData', timeToPlot, 'YData', dataToPlot(:,2)); % Update Force 2
    end
    if numForceChannels == 3
        set(forcePlots(3), 'XData', timeToPlot, 'YData', dataToPlot(:,3)); % Update Force 3
    end

    % Update X and Y axis limits
    if timeToPlot(end) > displayTime
        xlim(ax, [timeToPlot(end)-displayTime, timeToPlot(end)]);
    else
        xlim(ax, [0 displayTime]);
    end
    ylim(ax, [-1.2 1.2] * max(abs(data(:))));
end
