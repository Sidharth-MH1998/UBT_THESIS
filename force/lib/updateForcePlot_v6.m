function updateForcePlot_v6(ax, forceLines, data, fs_force, numForceChannels, displayTime, bufferTime, totalElapsedTime)
    % Time vector for the data (real time, continuously increasing)
    realTime = totalElapsedTime + (0:size(data,1)-1) / fs_force;
    
    % Extract the time range for the last 'displayTime' seconds
    maxSamples = displayTime * fs_force;
    if size(data,1) > maxSamples
        dataToPlot = data(end-maxSamples+1:end, :);
        timeToPlot = realTime(end-maxSamples+1:end);
    else
        dataToPlot = data;
        timeToPlot = realTime;
    end
    
    % Update the animated lines with new data points
    for i = 1:numForceChannels
        clearpoints(forceLines(i));  % Clear previous points
        addpoints(forceLines(i), timeToPlot, dataToPlot(:,i));  % Add new points
    end
    
    % Update the y-limits dynamically based on the new data
    minData = min(dataToPlot(:));
    maxData = max(dataToPlot(:));
%     ylim(ax, [minData - abs(minData)*0.1, maxData + abs(maxData)*0.1]);  % Add a small margin
    ylim(ax, [-10, 110]);  % Add a small margin
    
    % Update the x-limits to show the last 'displayTime' seconds plus bufferTime
    xlim(ax, [max(0, timeToPlot(end)-displayTime), timeToPlot(end) + bufferTime]);

%     if timeToPlot(end) < displayTime
%         xlim(ax, [ 0, displayTime + bufferTime]);
%     else
%         xlim(ax, [max(0, timeToPlot(end)-displayTime), timeToPlot(end) + bufferTime]);
%     end
end
