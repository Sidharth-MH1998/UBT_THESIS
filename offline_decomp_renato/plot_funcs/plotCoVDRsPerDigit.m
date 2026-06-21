function plotCoVDRsPerDigit(subjectID, spikes_g1, spikes_g2, all_force10, all_force20, fs, fs_force)
    % Function to compute and plot CoV of discharge rates (DRs) as violin plots
    % grouped by cohorts for each digit and force level, with all plots as subplots
    % in a single figure.

    % Inputs:
    % subjectID - ID of the subject being analyzed
    % spiketrains_g1, spiketrains_g2 - Spiketrain data for grids 1 and 2
    % all_force10, all_force20 - Force data for 10% and 20% force levels
    % fs - Sampling frequency of spiketrains
    % fs_force - Sampling frequency of force data
    
    % Get dimensions
    digits = size(spikes_g1, 1);
    fLevels = size(spikes_g1, 2);
    trials = size(spikes_g1, 3);

    % Define parameters
    firingThreshHz = 2; % Minimum spiking frequency for active MUs
    restThresh = 0.5; % Time (s) between spikes to transition from active to inactive
    minActiveDuration = 1; % Minimum duration for an active period

    % Colors for cohorts (to match smoothed DR plots)
    cohortColors = lines(4); % Adjust if more cohorts are needed

    % Create a figure for all subplots
    figure('Name', ['CoV DRs - Subject ' num2str(subjectID)], 'NumberTitle', 'off');
    
    % Iterate over digits and force levels
    plotIndex = 1; % Counter for subplot index
    for d = 1:digits
        for f = 1:fLevels
            % Initialize storage for CoV data for each cohort
            covData = cell(1, 4); % Four cohorts

            for t = 1:trials
                disp(['Processing digit ', num2str(d), ', force level ', num2str(f), ', trial ', num2str(t)])
                % Get spiketrains for current trial
                spiketrain_g1 = spikes_g1{d, f, t};
                spiketrain_g2 = spikes_g2{d, f, t};
    
                % Force data
                if f == 1 % Force level 10%
                    force = squeeze(all_force10(d, t, :, :));
                    cohortRanges = [0, 2.5, 5, 7.5, max(force(d,:)) + 0.01];
                else % Force level 20%
                    force = squeeze(all_force20(d, t, :, :));
                    cohortRanges = [0, 5, 10, 15, max(force(d,:)) + 0.01];
                end

                % Process trial and aggregate CoV data
                covDRs = processTrial(spiketrain_g1, spiketrain_g2, force(d,:), ...
                    cohortRanges, firingThreshHz, fs, fs_force, restThresh, minActiveDuration);

                % Append CoV data to the respective cohort
                for c = 1:4
                    covData{c} = [covData{c}; covDRs{c}];
                end
            end

            % Create a subplot for the current digit and force level
            subplot(digits, fLevels, plotIndex);
            plotIndex = plotIndex + 1;

            plotViolinByCohort(covData, cohortColors);
            xlabel('Cohort');
            ylabel('CoV of DRs');
            title(['Digit ' num2str(d) ', Force ' num2str(f * 10) '% MVC']);
            grid on;
        end
    end
end

function covDRs = processTrial(spiketrain_g1, spiketrain_g2, force, ...
    cohortRanges, firingThreshHz, fs, fs_force, restThresh, minActiveDuration)
    % Helper function to process a single trial and compute CoV of DRs

    % Get active periods for both grids
    activePeriods_g1 = find_MU_active_periods_v2(spiketrain_g1, firingThreshHz, fs, restThresh, minActiveDuration, 0);
    activePeriods_g2 = find_MU_active_periods_v2(spiketrain_g2, firingThreshHz, fs, restThresh, minActiveDuration, 0);

    % Recruitment thresholds
    recruitTimes_g1 = cellfun(@(x) min(x, [], "all"), activePeriods_g1);
    recruitTimes_g2 = cellfun(@(x) min(x, [], "all"), activePeriods_g2);
    recruitThresh_g1 = force(floor(recruitTimes_g1 .* fs_force));
    recruitThresh_g2 = force(floor(recruitTimes_g2 .* fs_force));

    % Smooth discharge rates
    smoothedDRs_g1 = smoothDischargeRates_SVR(spiketrain_g1, activePeriods_g1, fs, 0);
    smoothedDRs_g2 = smoothDischargeRates_SVR(spiketrain_g2, activePeriods_g2, fs, 0);

    % Compute CoV of DRs per cohort
    covDRs = computeCoVDRs(smoothedDRs_g1, smoothedDRs_g2, recruitThresh_g1, recruitThresh_g2, cohortRanges);
end

function plotViolinByCohort(covData, cohortColors)
    % Function to plot violin plots grouped by cohorts with scatter points
    numCohorts = length(covData);
    hold on;

    % Iterate over cohorts
    for c = 1:numCohorts
        data = covData{c};
        if isempty(data)
            continue;
        end

        % Kernel density estimation
        [f, xi] = ksdensity(data, 'Bandwidth', 0.2, 'Support', 'positive');
        f = f / max(f) * 0.35; % Normalize and set violin width

        % Violin plot
        fill([c - f, fliplr(c + f)], [xi, fliplr(xi)], cohortColors(c, :), ...
            'EdgeColor', 'none', 'FaceAlpha', 0.5);

        % Scatter points
        jitter = (rand(size(data)) - 0.5) * 0.2; % Add jitter for scatter points
        scatter(c + jitter, data, 15, 'filled', ...
            'MarkerFaceAlpha', 0.6, 'MarkerEdgeAlpha', 0, ...
            'MarkerFaceColor', cohortColors(c, :));
    end

    % Set axis properties
    xlim([0, numCohorts + 1]);
    set(gca, 'XTick', 1:numCohorts);
    hold off;
end