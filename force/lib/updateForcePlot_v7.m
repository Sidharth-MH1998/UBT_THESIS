function updateForcePlot_v7(ax, forceLines, data, fs_force, numForceChannels, displayTime, bufferTime, forceTarget)
    % Time vector for the data
    time = (0:size(data,1)-1) / fs_force;
    
    % Extract the time range for the last 'displayTime' seconds
    maxSamples = displayTime * fs_force;
    if size(data,1) > maxSamples
        dataToPlot = data(end-maxSamples+1:end, :);
        timeToPlot = time(end-maxSamples+1:end);
    else
        dataToPlot = data;
        timeToPlot = time;
    end
    
    % Update the animated lines with new data points
    for i = 1:numForceChannels
        clearpoints(forceLines(i));  % Clear previous points
        addpoints(forceLines(i), timeToPlot, dataToPlot(:,i));  % Add new points
    end
    
    % Update the y-limits if we are in recording force tracking mode
    ylim(ax, [-10 , forceTarget + 10]);
    
    % Update the x-limits to show the last 'displayTime' seconds plus bufferTime
    if timeToPlot(end) < displayTime
        xlim(ax, [ 0, displayTime + bufferTime]);
    else
        xlim(ax, [max(0, timeToPlot(end)-displayTime), timeToPlot(end) + bufferTime]);
    end

end