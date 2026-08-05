function updateForcePlot_v4(ax, forceLines, data, fs_force, numForceChannels, displayTime)
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
    
    % Update the y-limits dynamically based on the new data
    minData = min(dataToPlot(:));
    maxData = max(dataToPlot(:));
    ylim(ax, [minData - abs(minData)*0.1, maxData + abs(maxData)*0.1]);  % Add a small margin
    
    % Update the x-limits to show the last 'displayTime' seconds
    xlim(ax, [max(0, timeToPlot(end)-displayTime), timeToPlot(end)]);
end