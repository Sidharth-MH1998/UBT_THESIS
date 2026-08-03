function plotScatterJitter(varargin)
    % plotScatterJitter creates a scatter plot with jitter and transparency
    % from a variable number of input vectors. Each input vector can have variable lengths.
    
    % Number of data sets
    numDataSets = length(varargin);
    
    % Hold the current figure
    figure;
    hold on;
    
    % Colors for scatter points
    colors = lines(numDataSets);
    
    % Plot each data vector as a scatter plot with jitter and transparency
    for i = 1:numDataSets
        data = varargin{i};
        
        % Add jitter to the x-axis
        jitter = (rand(size(data)) - 0.5) * 0.1; % Adjust the jitter range as needed
        
        % Scatter plot with transparency
        scatter(i + jitter, data, 15, 'filled', 'MarkerFaceAlpha', 0.2, 'MarkerEdgeAlpha', 0.2, 'MarkerEdgeColor', colors(i,:), 'MarkerFaceColor', colors(i,:));
    end
    
    % Set x-axis labels
    set(gca, 'XTick', 1:numDataSets);
    xlim([0, numDataSets + 1]);
    
    % Release the hold on the current figure
    hold off;
end
