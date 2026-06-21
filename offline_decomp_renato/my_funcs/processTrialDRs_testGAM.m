function [smoothedDRs, meanDR, activePeriods, recruitThresh, covDRs, recruitThresh2, covDRs2, b, rmse]  ... 
     = processTrialDRs(spiketrain, meanDR, force, cohortRanges, fs, fs_force, firingThreshHz, restThresh, minActiveDuration)

    % Helper function to process a single trial discharge rates
    % Inputs:
    % spiketrain - Spiketrain data for the trial (nMUs x 1)
    % meanDR - mean DR of each MU (samples x nMUs)
    % force - Force data vector for the trial
    % fs - Sampling frequency of spiketrains
    % fs_force - Sampling frequency of force data
    % cohortRanges - Array (1 x numCohorts+1) specifying cohort threshold edges
    % firingThreshHz, restThresh, minActiveDuration: parameters to find MU spike trains active periods

    % Get active periods for both grids
    activePeriods = find_MU_active_periods_v2(spiketrain, firingThreshHz, fs, restThresh, minActiveDuration, 0);

    % Recruitment thresholds
    recruitTimes = cellfun(@(x) min(x, [], "all"), activePeriods);
    recruitThresh = force(floor(recruitTimes .* fs_force));

    % We only focus on the

    % We only keep the MUs with active periods over 55 seconds
    activeDurations = cellfun(@(x) max(x,[],"all") - min(x,[],"all"), activePeriods);
    activeMUs = find(activeDurations>55);
    spiketrain = spiketrain(:,activeMUs);
    meanDR = meanDR(activeMUs);
    activePeriods = activePeriods(activeMUs);
    recruitThresh = recruitThresh(activeMUs);
    recruitThresh2 = recruitThresh; % copy to be updated later

    % Smooth discharge rates
    smoothedDRs = smoothDischargeRates_SVR(spiketrain, activePeriods, fs, 0);

    % Compute CoV of DRs
    covDRs = [];
    for muIdx = 1:length(smoothedDRs)
        smoothedDR = smoothedDRs{muIdx}(:, 2);
        muMean = mean(smoothedDR);
        muStd = std(smoothedDR);
        muCV = muStd / muMean;
        covDRs = [covDRs; muCV];
    end

    covDRs2 = covDRs; % to be updated later

    % Compute regression coefficients
    [smoothedDRs_sampled, standTime, recruitThresh] = smoothDRs_SVR_standardised(spiketrain, activePeriods, force, fs, fs_force, fs);
    smoothedDRs_sampled = smoothedDRs_sampled'; % features in columns
    % Resample the force signal to match the standard time vector
    timeForce = (0:length(force) - 1) / fs_force;
    force_sampled = interp1(timeForce, force, standTime, 'linear', 0)'; 

%     % Apply dynamic sampling
%     fs_middle = 100;
%     focus_duration = 12;
%     [smoothedDRs_sampled, force_sampled] = dynamicSampling(smoothedDRs_stand', force_resamp, fs, fs_middle, focus_duration);

    % Fit Generalized Additive Model (GAM)
    gamModel = fitrgam(array2table(smoothedDRs_sampled), force_sampled, 'Interactions', 0);

    % Identify important features using partial dependence
    figure;
    for i = 1:size(smoothedDRs_sampled, 2)
        subplot(ceil(sqrt(size(smoothedDRs_sampled, 2))), ceil(sqrt(size(smoothedDRs_sampled, 2))), i);
        plotPartialDependence(gamModel, i);
        title(['MU ', num2str(i)]);
    end

    % Extract partial dependence data for the first MU (column 1)
    [mu1_effect, mu1_values, ~] = partialDependence(gamModel, 1);

    % Extract feature importance from GAM
    b = gamModel.Beta;

    % Predict the curve using the GAM model
    predictions = predict(gamModel, array2table(smoothedDRs_sampled));

    % Compute RMSE
    rmse = sqrt(mean((force_sampled - predictions).^2));

end
