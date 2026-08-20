function forceLines = initializeForcePlot(ax_f, numForceChan)
    colors = lines(numForceChan);
    forceLines = gobjects(numForceChan, 1);

    for i = 1:numForceChan
        forceLines(i) = animatedline(ax_f, 'Color', colors(i, :), 'LineWidth', 1.5);
    end

    legend(ax_f, {'Load cell 1', 'Load cell 2', 'Load cell 3'}, 'Location', 'northwest');
end