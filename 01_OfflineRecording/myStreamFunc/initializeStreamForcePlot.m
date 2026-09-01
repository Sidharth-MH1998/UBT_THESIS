function forceLines = initializeStreamForcePlot(ax_f, numForceChan)
    colors = lines(numForceChan);
    forceLines = gobjects(numForceChan, 1);

    channelLabels = {'Thumb', 'Index finger', 'Middle finger'};

    for i = 1:numForceChan
        forceLines(i) = animatedline(ax_f, ...
            'Color', colors(i, :), ...
            'LineWidth', 1.5, ...
            'DisplayName', channelLabels{i});
    end

    legend(ax_f, forceLines, channelLabels, 'Location', 'northwest');
end
