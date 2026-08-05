% Function to initialize force plot with line objects
function forceLines = initializeForcePlotWithLines(ax, numForceChannels)
    forceLines = gobjects(1, numForceChannels);
    hold(ax, 'on');
    for i = 1:numForceChannels
        forceLines(i) = plot(ax, NaN, NaN, 'LineWidth', 2);  % Initialize line object
    end
    hold(ax, 'off');
end