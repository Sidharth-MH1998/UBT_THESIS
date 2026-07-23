function updateForcePlot_v8(ax, forceLines, data, fs_force, numForceChannels, displayTime, bufferTime, forceTarget, currentForceIndex)
    % totalSamples is now set to the number of valid data points
    totalSamples = currentForceIndex;
    
    % Time vector for the valid data
    time = (0:totalSamples-1) / fs_force;
    
    % Determine the maximum number of samples to plot
    maxSamples = displayTime * fs_force;
    
    if totalSamples >= maxSamples
        % Extract the latest maxSamples
        dataToPlot = data(totalSamples - maxSamples + 1:totalSamples, :);
        timeToPlot = time(totalSamples - maxSamples + 1:totalSamples);
    else
        % Plot all the data collected so far
        dataToPlot = data(1:totalSamples, :);
        timeToPlot = time;
    end
    
    % Update the animated lines with new data points
    for i = 1:numForceChannels
        clearpoints(forceLines(i));  % Clear previous points
        addpoints(forceLines(i), timeToPlot, dataToPlot(:, i));  % Add new points
    end
    
    % Update the y-limits
    ylim(ax, [-10, forceTarget + 10]);
    
    % Update the x-limits to show the last 'displayTime' seconds plus bufferTime
    if timeToPlot(end) < displayTime
        xlim(ax, [0, displayTime + bufferTime]);
    else
        xlim(ax, [timeToPlot(end) - displayTime, timeToPlot(end) + bufferTime]);
    end
end