function emgLines = initializeEMGPlot(ax, numEMGChannels)
    % Initialize animated lines for each EMG channel
    emgLines = gobjects(1, numEMGChannels);  % Preallocate array for EMG lines
    for i = 1:numEMGChannels
        emgLines(i) = animatedline(ax, 'Color', rand(1, 3));  % Random colors for EMG channels
    end
end
