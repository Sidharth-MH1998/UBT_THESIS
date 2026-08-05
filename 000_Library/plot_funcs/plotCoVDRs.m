function plotCoVDRs(subjectID, spikes_g1, spikes_g2, all_force10, all_force20, fs, fs_force)
    % Function to compute and plot CoV of discharge rates (DRs) as violin plots
    % grouped by cohorts across all trials for a given subject.

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

    % Initialize storage for CoV data for each cohort
    covData10 = cell(1, 4); % 4 cohorts for 10% force
    covData20 = cell(1, 4); % 4 cohorts for 20% force

    % Define parameters
    firingThreshHz = 2; % Minimum spiking frequency for active MUs
    restThresh = 0.5; % Time (s) between spikes to transition from active to inactive
    minActiveDuration = 1; % Minimum duration for an active period

    % Colors for cohorts (to match smoothed DR plots)
    cohortColors = lines(4); % Adjust if more cohorts are needed
    
    for d = 1:digits
        for f = 1:fLevels
            for t = 1:trials
                disp(['Processing digit ', num2str(d), ', force level ', num2str(f), ', trial ', num2str(t)])
                % Get spiketrains for current trial
                spiketrain_g1 = spikes_g1{d, f, t};
                spiketrain_g2 = spikes_g2{d, f, t};
    
                % Force data for both levels
                if f == 1 % Force level 10%
                    force10 = squeeze(all_force10(d, t, :, :));
                    cohortRanges10 = [0, 2.5, 5, 7.5, max(force10(d,:)) + 0.01];
                    covDRs10 = processTrial(spiketrain_g1, spiketrain_g2, force10(d,:), ...
                        cohortRanges10, firingThreshHz, fs, fs_force, restThresh, minActiveDuration);
                    for c = 1:4
                        covData10{c} = [covData10{c}; covDRs10{c}];
                    end
                else % Force level 20%
                    force20 = squeeze(all_force20(d, t, :, :));
                    cohortRanges20 = [0, 5, 10, 15, max(force20(d,:)) + 0.01];
                    covDRs20 = processTrial(spiketrain_g1, spiketrain_g2, force20(d,:), ...
                        cohortRanges20, firingThreshHz, fs, fs_force, restThresh, minActiveDuration);
                    for c = 1:4
                        covData20{c} = [covData20{c}; covDRs20{c}];
                    end
                end
            end
        end
    end

    % Create violin plots
    figure;

    % Plot for 10% force level
    subplot(1, 2, 1);
    plotViolinByCohort(covData10, cohortColors);
    xlabel('Cohort');
    ylabel('CoV of DRs');
    title(['Force Level: 10% MVC - Subject ' num2str(subjectID)]);
    grid on;

    % Plot for 20% force level
    subplot(1, 2, 2);
    plotViolinByCohort(covData20, cohortColors);
    xlabel('Cohort');
    ylabel('CoV of DRs');
    title(['Force Level: 20% MVC - Subject ' num2str(subjectID)]);
    grid on;
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