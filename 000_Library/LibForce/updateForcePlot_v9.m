function updateForcePlot_v9(ax_f, forceLines, forceData, fs_force, numForceChan, displayTime, bufferTime, forceTarget, currentForceIndex, lastPlottedIdx)
    % Get the current total number of samples
    totalSamples = currentForceIndex;

    % Time vector for the valid data
    time = (0:totalSamples-1) / fs_force;

    % Determine the maximum number of samples to plot
    maxSamples = displayTime * fs_force;
    
    % If we have more samples than maxSamples, plot only the latest maxSamples
    if totalSamples > maxSamples
        newData = forceData(totalSamples - maxSamples + 1:totalSamples, :);
        newTime = time(totalSamples - maxSamples + 1:totalSamples);
    else
        newData = forceData(1:totalSamples, :);
        newTime = time;
    end
    
    % Plot only the new points since the last plotted index
    if lastPlottedIdx < totalSamples
        newIdxRange = lastPlottedIdx+1:totalSamples;
        newTimeRange = (newIdxRange - 1) / fs_force;
        
        for i = 1:numForceChan
            % Add only new points to the animated line
            addpoints(forceLines(i), newTimeRange, forceData(newIdxRange, i));
        end
    end
    
    % Update the y-limits
    ylim(ax_f, [-10, forceTarget + 10]);
    
    % Update the x-limits to show the last 'displayTime' seconds plus bufferTime
    if newTime(end) < displayTime
        xlim(ax_f, [0, displayTime + bufferTime]);
    else
        xlim(ax_f, [newTime(end) - displayTime, newTime(end) + bufferTime]);
    end
end
