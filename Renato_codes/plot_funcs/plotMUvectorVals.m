function plotMUvectorVals(varGrids, subjects, digLabels, forces, trials, varLabel)
    % Function to plot MU values for two grids across subjects, digits, and force levels in grouped bar plots
    %
    % Parameters:
    %   varGrids: A cell array (1 x numGrids), each containing a cell array 
    %             of dimensions subjects x digits x forces x trials. Each cell has a 
    %             (1 x MUs) vector representing values of a variable described by the varLabel.
    %   subjects: Cell array / vector of strings for subject labels
    %   digLabels: Cell array / vector of strings for digit labels
    %   forces: Cell array / vector of strings for force levels
    %   trials: Number of trials
    %   varLabel: Label for the variable to be loaded

    % Validate input
    if numel(varGrids) ~= 2
        error('This function is designed for two grids. Provide exactly two grids.');
    end
    
    % Get dimensions
    numSubjects = numel(subjects);
    numDigits = numel(digLabels);
    numForces = numel(forces);
    numConditions = numDigits * numForces;

    % Initialize storage for MU values
    valArray = cell([numSubjects, numDigits, numForces]);

    % Process each grid
    for S = 1:numSubjects
        for d = 1:numDigits
            for f = 1:numForces
                for t = 1:trials
                    for g = 1:2
                        temp = varGrids{g}{S, d, f, t};
                        if or(~isempty(temp), ~isnan(temp)) % if there are MUs and non NaN values
                            valArray{S, d, f} = [valArray{S, d, f}, temp]; % add values to cell
                        end
                    end
                end
            end
        end
    end

    % Compute means and standard deviations for each condition
    barData = zeros(numSubjects, numConditions);
    errData = zeros(numSubjects, numConditions);
    conditionLabels = cell(1, numConditions);
    colIdx = 1;
    for d = 1:numDigits
        for f = 1:numForces
            conditionLabels{colIdx} = sprintf('%s - %s%%', digLabels{d}, forces{f});
            for S = 1:numSubjects
                values = valArray{S, d, f};
                if ~isempty(values)
                    barData(S, colIdx) = mean(values,'omitnan'); % Mean values
                    errData(S, colIdx) = std(values,'omitnan');  % Standard deviation
                end
            end
            colIdx = colIdx + 1;
        end
    end

    % Compute overall mean and std for all conditions per subject
    overallMeans = zeros(1, numSubjects);
    overallStds = zeros(1, numSubjects);
    for S = 1:numSubjects
        allValues = [];
        for d = 1:numDigits
            for f = 1:numForces
                allValues = [allValues, valArray{S, d, f}];
            end
        end
        if ~isempty(allValues)
            overallMeans(S) = mean(allValues,'omitnan');
            overallStds(S) = std(allValues,'omitnan');
        end
    end

    % Plotting
    figure;

    % First subplot: Grouped bar chart per condition
    subplot(2, 1, 1);
    hold on;

    % Bar width and positions
    groupWidth = 0.8;
    barWidth = groupWidth / numConditions;
    x = 1:numSubjects;

    colors = lines(numConditions); % Colors for each condition
    barHandles = gobjects(1, numConditions);

    for c = 1:numConditions
        % Shift bar positions for grouping
        offset = (c - (numConditions + 1) / 2) * barWidth;
        xShifted = x + offset;

        % Plot bars and error bars
        barHandles(c) = bar(xShifted, barData(:, c), barWidth, 'FaceColor', colors(c, :), ...
            'EdgeColor', 'none', 'DisplayName', conditionLabels{c});
        errorbar(xShifted, barData(:, c), errData(:, c), 'k.', 'CapSize', 10, 'LineWidth', 1);
    end

    % Customize plot
    xlabel('Subjects');
    ylabel(varLabel);
    title('Grouped Bar Plot of MU Values per Subject and Condition');
    legend(barHandles, 'Location', 'northeastoutside');
    xticks(1:numSubjects);
    xticklabels(arrayfun(@(s) strcat("S", subjects(s)), 1:numSubjects, 'UniformOutput', false));
    xlim([0.5, numSubjects + 0.5]);
    grid on;
    hold off;

    % Second subplot: Overall mean and std per subject
    subplot(2, 1, 2);
    hold on;

    % Plot bars and error bars
    bar(x, overallMeans, 0.6, 'FaceColor', [0.2, 0.6, 0.8], 'EdgeColor', 'none');
    errorbar(x, overallMeans, overallStds, 'k.', 'CapSize', 10, 'LineWidth', 1);

    % Customize plot
    xlabel('Subjects');
    ylabel(varLabel);
    title('Overall Mean MU Values per Subject');
    xticks(1:numSubjects);
    xticklabels(arrayfun(@(s) strcat("S", subjects(s)), 1:numSubjects, 'UniformOutput', false));
    xlim([0.5, numSubjects + 0.5]);
    grid on;
    hold off;

    sgtitle('MU Values Analysis'); % Overall title for the figure
end