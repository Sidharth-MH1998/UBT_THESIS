function plotViolin(varargin)
    % plotViolin creates a violin plot from a variable number of input vectors
    % Each input vector can have variable lengths
    % Optional scatter plot with transparency can be enabled via an argument
    
    % Check if the last argument is 'scatter'
    plotScatter = false;
    if ischar(varargin{end}) && strcmp(varargin{end}, 'scatter')
        plotScatter = true;
        varargin(end) = []; % Remove 'scatter' from the input arguments
    end
    
    % Number of data vectors
    numDataSets = length(varargin);
    
    % Hold the current figure
    figure;
    hold on;
    
    % Colors for scatter points
    colors = lines(numDataSets);

    % Scaling factor for the violin width
    violinWidth = 0.35;
    
    % Plot each data vector as a violin plot
    for i = 1:numDataSets
        data = varargin{i};
        
        % Kernel density estimation
        [f, xi] = ksdensity(data, 'Bandwidth', 0.2, 'Support', 'positive');
        f = f / max(f) * violinWidth; % Normalize for consistent width and scale according to preferred width
        
        % Violin plot (fill area)
        fill([i - f, fliplr(i + f)], [xi, fliplr(xi)], [0.5 0.5 0.5], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
        
        % Scatter plot with transparency
        if plotScatter
            jitter = (rand(size(data)) - 0.5) * 0.2; % Add jitter for x-axis
            scatter(i + jitter, data, 15, 'filled', 'MarkerFaceAlpha', 0.2, 'MarkerEdgeAlpha', 0, 'MarkerEdgeColor', colors(i,:), 'MarkerFaceColor', colors(i,:));
        end
    end
    
    % Set x-axis labels
    set(gca, 'XTick', 1:numDataSets);
    xlim([0, numDataSets + 1]);
    
    % Release the hold on the current figure
    hold off;
end
