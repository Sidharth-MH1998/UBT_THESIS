function [forceLines] = initializeForcePlot(ax, numForceChannels)
    colors = ['r', 'b', 'g'];  % Define colors for each force channel
    forceLines = gobjects(1, numForceChannels);  % Initialize array for animated lines
%     forceLabels = {};

    % Create an animated line for each force channel
    for i = 1:numForceChannels
        forceLines(i) = animatedline(ax, 'Color', colors(i), 'LineWidth', 1.5);
%         forceLabels{end+1} = strcat("Force channel ",num2str(i));
    end

%     legend(ax,forceLabels)
end