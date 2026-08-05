% Update force plot using line objects
function updateForcePlotWithLines(ax, forceLines, data, fs_force, numForceChannels, displayTime, bufferTime)
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
    
    % Update the line objects with new data points
    for i = 1:numForceChannels
        set(forceLines(i), 'XData', timeToPlot, 'YData', dataToPlot(:,i));  % Set new data
    end
    
    % Update the y-limits dynamically based on the new data
    minData = min(dataToPlot(:));
    maxData = max(dataToPlot(:));
    ylim(ax, [minData - abs(minData)*0.1, maxData + abs(maxData)*0.1]);  % Add a small margin
    
    % Update the x-limits to show the last 'displayTime' seconds plus bufferTime
    xlim(ax, [max(0, timeToPlot(end)-displayTime), timeToPlot(end) + bufferTime]);
end