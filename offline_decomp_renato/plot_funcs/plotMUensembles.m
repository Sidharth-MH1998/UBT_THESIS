function plotMUensembles(smoothedDRs, recruitThresh, force, fs_force, cohortRanges)
    % Generates ensemble plots for smoothed MU discharge rates.
    %
    % Inputs:
    %   smoothedDRs:        Cell array (1 x nMUs), each containing [time, rate].
    %   recruitThresh:      Vector (1 x nMUs), recruitment thresholds (force levels).
    %   force:              Vector, normalized reference force curve (0-100% range).
    %   fs_force:           Force sampling frequency in Hz.
    %   cohortRanges:       Vector, cohort boundaries (e.g., [0, 3, 6, ..., 100]).
    %
    % Outputs:
    %   A figure showing ensemble discharge rates.

    nMUs = length(smoothedDRs);
    nCohorts = length(cohortRanges) - 1;

    % Assign each MU to a cohort based on its recruitment threshold
    cohorts = cell(1, nCohorts);
    for c = 1:nCohorts
        cohorts{c} = find(recruitThresh >= cohortRanges(c) & ...
                          recruitThresh < cohortRanges(c+1));
    end

    % Time vector
    time_force = (0:length(force)-1) / fs_force;

    % Initialize figure
    colors = lines(nCohorts); % Generate distinct colors for each cohort
    yOffset = (cohortRanges(2)-cohortRanges(1))*5; % Offset for separating cohorts in the Y-axis equal to distance between cohorts
    cAlpha = 0.03; % transparency for line colour

    hold on;
    for c = 1:nCohorts
        % Get MUs in the current cohort
        cohortMUs = cohorts{c};
        cohortData = [];

        % Plot individual MU discharge rates
        for mu = cohortMUs
            if ~isempty(smoothedDRs{mu})
                % Extract time and rate
                time = smoothedDRs{mu}(:, 1);
                rate = smoothedDRs{mu}(:, 2);
                % Plot individual MU with transparency
                plot(time, rate + (c-1)*yOffset, 'Color', [colors(c, :) cAlpha], 'LineWidth', 0.2);

                % Interpolate rates to a standardized time grid
                commonTime = linspace(min(time), max(time), 1000); % Standardized time grid
                interpolatedRate = interp1(time, rate, commonTime, 'linear', NaN);
                cohortData = [cohortData; interpolatedRate]; % Stack data for averaging
                cohortTimes = commonTime; % Use standardized time for cohort average
            end
        end

        % Plot the cohort average
        if ~isempty(cohortData)
            avgRate = nanmean(cohortData, 1); % Compute mean across MUs, ignoring NaNs
            plot(cohortTimes, avgRate + (c-1)*yOffset, 'Color', colors(c, :), 'LineWidth', 1.5);
        end
    end

%     % Plot reference force curve with a secondary axis
%     plot(time_force, force, 'k', 'LineWidth', 3);
%     hold off;
%     title('Smoothed Discharge Rates');
%     xlabel('Time (s)');
%     ylabel('Discharge Rate (pps)');
%     ylim([-2, nCohorts*yOffset + 10]);
%     grid on;

    % Plot the reference force curve with a secondary axis
    yyaxis right;
    plot(time_force, force, 'Color',[0 0 0 0.7], 'LineWidth', 3); % in black with some transparency
    ylabel('Force (% MVC)');
    ylim([-2, max(force) + 2]);
    set(gca, 'YColor', 'k'); % Set force axis color to black

    % Label axes and configure plot
    yyaxis left;
    xlabel('Time (s)');
    ylabel('Discharge Rate (pps)');
    title('Smoothed Discharge Rates');
    ylim([-2, nCohorts*yOffset + 10]);
    grid on;

%     % Add a small vertical scale bar for discharge rates
%     xScaleBar = min(time_force) - 0.5; % Place the scale bar slightly to the left of the plot
%     yScaleStart = 0;
%     yScaleEnd = 10; % Define the range of the scale bar (e.g., 10 pps)
%     plot([xScaleBar, xScaleBar], [yScaleStart, yScaleEnd], 'k-', 'LineWidth', 2); % Draw scale bar
%     text(xScaleBar, yScaleEnd/2, '10 pps', 'HorizontalAlignment', 'right', ...
%          'VerticalAlignment', 'middle', 'FontSize', 10);

%     % Add legend
%     legendLabels = arrayfun(@(c) sprintf('Cohort %d', c), 1:nCohorts, 'UniformOutput', false);
%     legend([legendLabels, {'Force'}], 'Location', 'Best');
    hold off;

end