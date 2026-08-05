function emgLines = initializeEMGPlotWithLines(ax, numEMGChannels)
    % Initialize line objects for each EMG channel
    emgLines = gobjects(1, numEMGChannels);  % Preallocate array for EMG lines
    hold(ax, 'on');
    for i = 1:numEMGChannels
        emgLines(i) = plot(ax, NaN, NaN, 'Color', rand(1, 3), 'LineWidth', 1.5);  % Initialize each line object
    end
    hold(ax, 'off');
end